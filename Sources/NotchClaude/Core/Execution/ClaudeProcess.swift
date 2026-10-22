import Foundation

final class ClaudeProcess {
    var onEvent: (([String: Any]) -> Void)?
    var onExit: (([String: Any]) -> Void)?

    private let launch: ClaudeLaunch
    private let logURL: URL
    private let process = Process()
    private let queue = DispatchQueue(label: "app.notchclaude.process")
    private let lock = NSLock()
    private var buffer = Data()
    private var errorData = Data()
    private var logHandle: FileHandle?
    private var cancelRequested = false

    init(launch: ClaudeLaunch, logURL: URL) {
        self.launch = launch
        self.logURL = logURL
    }

    var processIdentifier: Int32 { process.processIdentifier }

    func start() throws {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
        writeLog(launch.header)

        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.directory
        process.environment = launch.environment

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let group = DispatchGroup()
        group.enter()
        group.enter()
        group.enter()

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self.queue.async {
                    self.drain(final: true)
                    group.leave()
                }
            } else {
                self.queue.async { self.ingest(data) }
            }
        }

        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self.queue.async { group.leave() }
            } else {
                self.queue.async {
                    self.errorData.append(data)
                    if self.errorData.count > 64_000 { self.errorData = self.errorData.suffix(32_000) }
                }
            }
        }

        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            try? logHandle?.close()
            throw error
        }

        let payload = launch.input
        DispatchQueue.global(qos: .userInitiated).async {
            let writer = input.fileHandleForWriting
            try? writer.write(contentsOf: payload)
            try? writer.close()
        }

        group.notify(queue: queue) { self.finish() }
    }

    func stop() {
        lock.lock()
        cancelRequested = true
        lock.unlock()
        guard process.isRunning else { return }
        process.interrupt()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 9) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        drain(final: false)
    }

    private func drain(final: Bool) {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line)
        }
        if final, !buffer.isEmpty {
            handle(buffer)
            buffer.removeAll()
        }
    }

    private func handle(_ line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if (object["type"] as? String) != "stream_event" {
            try? logHandle?.write(contentsOf: line)
            try? logHandle?.write(contentsOf: Data([UInt8(ascii: "\n")]))
        }
        DispatchQueue.main.async { self.onEvent?(object) }
    }

    private func finish() {
        let stderr = String(decoding: errorData.suffix(6_000), as: UTF8.self)
        let exit: [String: Any] = [
            "type": "notchclaude_exit",
            "status": Int(process.terminationStatus),
            "cancelled": isCancelled,
            "stderr": stderr,
            "date": Date().timeIntervalSince1970
        ]
        writeLog(exit)
        try? logHandle?.close()
        logHandle = nil
        DispatchQueue.main.async {
            self.onExit?(exit)
            self.onEvent = nil
            self.onExit = nil
        }
    }

    private func writeLog(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        data.append(UInt8(ascii: "\n"))
        try? logHandle?.write(contentsOf: data)
    }
}
