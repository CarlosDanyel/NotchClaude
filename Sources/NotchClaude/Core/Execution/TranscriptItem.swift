import Foundation

struct AttachmentReference: Hashable {
    var path: String
    var name: String
    var isImage: Bool
}

struct ToolCall {
    var id: String
    var name: String
    var title: String
    var summary: String
    var detail: String
    var symbol: String
    var output: String?
    var isError = false
    var isDone = false
}

struct ResultInfo {
    var isError: Bool
    var subtype: String
    var text: String
    var costUSD: Double?
    var durationMs: Int?
    var numTurns: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var sessionId: String?
}

struct TranscriptItem: Identifiable {
    enum Kind {
        case prompt(text: String, attachments: [AttachmentReference], isResume: Bool, date: Date?)
        case assistant(text: String)
        case thinking(text: String)
        case tool(ToolCall)
        case system(text: String, symbol: String)
        case result(ResultInfo)
        case failure(text: String)
    }

    let id: String
    var kind: Kind
    var isNested = false
}
