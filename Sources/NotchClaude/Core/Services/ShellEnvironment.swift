import Foundation

final class ShellEnvironment {
    static let shared = ShellEnvironment()

    private static let marker = "__NOTCHCLAUDE_ENV__"
    private static let strippedKeys: Set<String> = [
        "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT", "CLAUDE_AGENT_SDK_VERSION",
        "_", "SHLVL", "PWD", "OLDPWD", "XPC_SERVICE_NAME", "XPC_FLAGS", "__CFBundleIdentifier"
    ]

    private let lock = NSLock()
    private var cached: [String: String]

    private init() {
        cached = ShellEnvironment.fallbackEnvironment()
    }

    var environment: [String: String] {
        lock.lock()
        let current = cached
        lock.unlock()
        let identity = ShellEnvironment.baseEnvironment().filter { ["HOME", "USER", "LOGNAME", "SHELL"].contains($0.key) }
        return current.merging(identity) { existing, fallback in existing.isEmpty ? fallback : existing }
    }

    func refresh(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let resolved = ShellEnvironment.loadLoginEnvironment() {
                self.lock.lock()
                self.cached = resolved
                self.lock.unlock()
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    func claudeExecutable(override: String) -> String? {
        let fileManager = FileManager.default
        let expanded = (override as NSString).expandingTildeInPath
        if !expanded.isEmpty, fileManager.isExecutableFile(atPath: expanded) { return expanded }
        let home = fileManager.homeDirectoryForCurrentUser.path
        let pathDirectories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = pathDirectories + [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        return candidates
            .map { ($0 as NSString).appendingPathComponent("claude") }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }

    private static var userShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let value = String(cString: shell)
            if !value.isEmpty { return value }
        }
        return "/bin/zsh"
    }

    private static func baseEnvironment() -> [String: String] {
        let info = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let user = NSUserName()
        return [
            "HOME": home,
            "USER": user,
            "LOGNAME": user,
            "SHELL": userShell,
            "TMPDIR": info["TMPDIR"] ?? NSTemporaryDirectory(),
            "LANG": info["LANG"] ?? "en_US.UTF-8",
            "TERM": "xterm-256color",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
    }

    private static func fallbackEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { !strippedKeys.contains($0.key) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        environment["PATH"] = (extra + current).reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }.joined(separator: ":")
        environment.merge(baseEnvironment().filter { $0.key != "PATH" }) { current, _ in current }
        return environment
    }

    private static func loadLoginEnvironment() -> [String: String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)
        process.arguments = ["-ilc", "printf '\\n\(marker)\\n'; /usr/bin/env -0"]
        process.environment = baseEnvironment()
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        var collected = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            collected = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        do { try process.run() } catch { return nil }
        if group.wait(timeout: .now() + 12) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()

        guard let text = String(data: collected, encoding: .utf8),
              let range = text.range(of: "\(marker)\n") else { return nil }
        var environment: [String: String] = [:]
        for entry in text[range.upperBound...].split(separator: "\0") {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            guard !key.isEmpty, !strippedKeys.contains(key) else { continue }
            environment[key] = String(entry[entry.index(after: separator)...])
        }
        guard environment["PATH"] != nil else { return nil }
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        return environment
    }
}
