import AppKit

enum LaunchAtLogin {
    static let label = "app.notchclaude.NotchClaude"

    private static let preferenceKey = "launchAtLogin"

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static var isInstalledLocation: Bool {
        let path = Bundle.main.bundlePath
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    static var isPreferred: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    static var isEnabled: Bool {
        guard let executable = Bundle.main.executablePath,
              let data = try? Data(contentsOf: agentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return false }
        return arguments.first == executable
    }

    static func synchronize() {
        guard isPreferred, isInstalledLocation, !isEnabled else { return }
        install()
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled {
            guard isInstalledLocation else { return false }
            return install()
        }
        try? FileManager.default.removeItem(at: agentURL)
        return true
    }

    @discardableResult
    private static func install() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "ThrottleInterval": 10
        ]
        do {
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

enum TerminalLauncher {
    static func resume(task: ClaudeTask, settings: AppSettings, shell: ShellEnvironment) {
        guard let sessionId = task.lastSessionId,
              let executable = shell.claudeExecutable(override: settings.claudePath) else { return }
        let command = ClaudeCommandBuilder.terminalCommand(executable: executable, sessionId: sessionId, settings: settings)
        let script = """
        #!/bin/zsh -il
        cd \(ClaudeCommandBuilder.shellQuote(task.directory)) || exit 1
        clear
        exec \(command)
        """
        let url = AppPaths.launchers.appendingPathComponent("resume-\(task.id.uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    static func revealDirectory(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}
