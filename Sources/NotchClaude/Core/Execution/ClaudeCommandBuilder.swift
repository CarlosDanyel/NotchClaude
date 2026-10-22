import Foundation

struct ClaudeLaunch {
    var executable: String
    var arguments: [String]
    var directory: URL
    var environment: [String: String]
    var input: Data
    var header: [String: Any]
}

struct RunPlan {
    var sessionId: String
    var isResume: Bool
    var prompt: String
    var attachments: [Attachment]
    var model: String
    var effort: String
    var title: String
    var directory: URL

    init(task: ClaudeTask, settings: AppSettings) {
        if task.hasPendingResume, let session = task.resumeSessionId, let prompt = task.nextPrompt {
            sessionId = session
            isResume = true
            self.prompt = prompt
            attachments = task.nextAttachments
        } else {
            sessionId = UUID().uuidString.lowercased()
            isResume = false
            prompt = task.prompt
            attachments = task.attachments
        }
        model = task.model ?? settings.defaultModel
        effort = task.effort ?? settings.defaultEffort
        title = task.title
        directory = task.directoryURL
    }
}

enum ClaudeCommandError: LocalizedError {
    case unreadableAttachment(String)

    var errorDescription: String? {
        switch self {
        case .unreadableAttachment(let name): return "Não foi possível ler o anexo \(name)"
        }
    }
}

enum ClaudeCommandBuilder {
    static func launch(plan: RunPlan, settings: AppSettings, executable: String, environment: [String: String]) throws -> ClaudeLaunch {
        ClaudeLaunch(
            executable: executable,
            arguments: arguments(plan: plan, settings: settings),
            directory: plan.directory,
            environment: environment,
            input: try inputMessage(plan: plan),
            header: header(plan: plan)
        )
    }

    static func arguments(plan: RunPlan, settings: AppSettings) -> [String] {
        var arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages"
        ]
        arguments += settings.skipPermissions ? ["--dangerously-skip-permissions"] : ["--permission-mode", "acceptEdits"]
        arguments += plan.isResume ? ["--resume", plan.sessionId] : ["--session-id", plan.sessionId, "--name", plan.title]
        if !plan.model.isEmpty { arguments += ["--model", plan.model] }
        if !plan.effort.isEmpty { arguments += ["--effort", plan.effort] }
        arguments += ArgumentSplitter.split(settings.extraArguments)
        return arguments
    }

    static func terminalCommand(executable: String, sessionId: String, settings: AppSettings) -> String {
        var parts = [shellQuote(executable), "--resume", shellQuote(sessionId)]
        if settings.skipPermissions { parts.append("--dangerously-skip-permissions") }
        return parts.joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func inputMessage(plan: RunPlan) throws -> Data {
        let files = plan.attachments.filter { !$0.isImage }
        var text = plan.prompt
        if !files.isEmpty {
            let list = files.map { "- \($0.url.path)" }.joined(separator: "\n")
            text += "\n\nArquivos anexados:\n\(list)"
        }

        var content: [[String: Any]] = [["type": "text", "text": text]]
        for image in plan.attachments where image.isImage {
            guard let data = try? Data(contentsOf: image.url) else {
                throw ClaudeCommandError.unreadableAttachment(image.originalName)
            }
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mediaType ?? "image/png",
                    "data": data.base64EncodedString()
                ]
            ])
        }

        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": content],
            "parent_tool_use_id": NSNull(),
            "session_id": ""
        ]
        var data = try JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static func header(plan: RunPlan) -> [String: Any] {
        [
            "type": "notchclaude_input",
            "prompt": plan.prompt,
            "resume": plan.isResume,
            "session_id": plan.sessionId,
            "date": Date().timeIntervalSince1970,
            "attachments": plan.attachments.map {
                ["path": $0.url.path, "name": $0.originalName, "isImage": $0.isImage]
            }
        ]
    }
}

enum ArgumentSplitter {
    static func split(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        var escaping = false
        for character in text {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" && quote != "'" {
                escaping = true
                hasToken = true
                continue
            }
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                hasToken = true
            } else if character.isWhitespace {
                if hasToken { result.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken { result.append(current) }
        return result
    }
}
