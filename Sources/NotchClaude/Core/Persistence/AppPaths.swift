import Foundation

enum AppPaths {
    static let base: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchClaude", isDirectory: true)

    static let storeFile = base.appendingPathComponent("store.json")
    static let attachments = base.appendingPathComponent("attachments", isDirectory: true)
    static let logs = base.appendingPathComponent("logs", isDirectory: true)
    static let launchers = base.appendingPathComponent("launchers", isDirectory: true)

    static func prepare() {
        for directory in [base, attachments, logs, launchers] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
