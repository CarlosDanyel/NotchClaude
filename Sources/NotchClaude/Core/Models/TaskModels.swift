import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case scheduled
    case queued
    case running
    case rateLimited
    case completed
    case failed
    case cancelled

    var label: String {
        switch self {
        case .scheduled: return "Agendada"
        case .queued: return "Aguardando"
        case .running: return "Executando"
        case .rateLimited: return "Tokens esgotados"
        case .completed: return "Concluída"
        case .failed: return "Erro"
        case .cancelled: return "Cancelada"
        }
    }

    var isPending: Bool { self == .scheduled || self == .queued || self == .rateLimited }
    var isFinished: Bool { self == .completed || self == .failed || self == .cancelled }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case never
    case hourly
    case daily
    case weekdays
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "Não repetir"
        case .hourly: return "A cada hora"
        case .daily: return "Todo dia"
        case .weekdays: return "Dias úteis"
        case .weekly: return "Toda semana"
        }
    }

    func nextDate(after now: Date, anchor: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .never:
            return nil
        case .hourly:
            let elapsed = now.timeIntervalSince(anchor)
            let steps = max(1, Int(floor(elapsed / 3600)) + 1)
            return anchor.addingTimeInterval(Double(steps) * 3600)
        case .daily:
            let parts = calendar.dateComponents([.hour, .minute], from: anchor)
            return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
        case .weekdays:
            let parts = calendar.dateComponents([.hour, .minute], from: anchor)
            var cursor = now
            for _ in 0..<8 {
                guard let candidate = calendar.nextDate(after: cursor, matching: parts, matchingPolicy: .nextTime) else { return nil }
                if !calendar.isDateInWeekend(candidate) { return candidate }
                cursor = candidate
            }
            return nil
        case .weekly:
            let parts = calendar.dateComponents([.weekday, .hour, .minute], from: anchor)
            return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
        }
    }
}

struct Attachment: Codable, Identifiable, Hashable {
    var id = UUID()
    var fileName: String
    var originalName: String
    var mediaType: String?

    var url: URL { AppPaths.attachments.appendingPathComponent(fileName) }
    var isImage: Bool { mediaType != nil }
}

enum RunOutcome: String, Codable {
    case success
    case failed
    case rateLimited
    case cancelled
    case interrupted
}

struct RunRecord: Codable, Identifiable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var outcome: RunOutcome?
    var sessionId: String
    var isResume: Bool
    var costUSD: Double?
    var inputTokens: Int?
    var outputTokens: Int?
    var numTurns: Int?
    var summary: String?

    var logURL: URL { AppPaths.logs.appendingPathComponent("\(id.uuidString).jsonl") }
    var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
}

struct ClaudeTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var prompt: String
    var directory: String
    var attachments: [Attachment] = []
    var model: String?
    var effort: String?
    var createdAt = Date()
    var scheduledAt: Date
    var anchorDate: Date
    var repeatRule: RepeatRule = .never
    var status: TaskStatus = .scheduled
    var statusDetail: String?
    var retryAt: Date?
    var resumeSessionId: String?
    var nextPrompt: String?
    var nextAttachments: [Attachment] = []
    var archivedAttachments: [Attachment] = []
    var finishedAt: Date?
    var runs: [RunRecord] = []

    var lastRun: RunRecord? { runs.last }
    var lastSessionId: String? { runs.last?.sessionId }
    var directoryURL: URL { URL(fileURLWithPath: directory) }
    var directoryName: String { directoryURL.lastPathComponent }
    var totalCost: Double { runs.compactMap(\.costUSD).reduce(0, +) }
    var hasPendingResume: Bool { resumeSessionId != nil && nextPrompt != nil }
    var allAttachments: [Attachment] { attachments + nextAttachments + archivedAttachments }

    mutating func clearPendingResume() {
        archivedAttachments += nextAttachments
        nextAttachments = []
        nextPrompt = nil
        resumeSessionId = nil
    }

    static func makeTitle(from prompt: String) -> String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Nova tarefa"
        return firstLine.count > 70 ? String(firstLine.prefix(70)) + "…" : firstLine
    }
}

extension ClaudeTask {
    private enum CodingKeys: String, CodingKey {
        case id, title, prompt, directory, attachments, model, effort, createdAt, scheduledAt, anchorDate
        case repeatRule, status, statusDetail, retryAt, resumeSessionId, nextPrompt, nextAttachments
        case archivedAttachments, finishedAt, runs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ClaudeTask.makeTitle(from: prompt)
        directory = try container.decodeIfPresent(String.self, forKey: .directory) ?? FileManager.default.homeDirectoryForCurrentUser.path
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        model = try container.decodeIfPresent(String.self, forKey: .model)
        effort = try container.decodeIfPresent(String.self, forKey: .effort)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt) ?? now
        anchorDate = try container.decodeIfPresent(Date.self, forKey: .anchorDate) ?? scheduledAt
        repeatRule = (try? container.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)) ?? .never
        status = (try? container.decodeIfPresent(TaskStatus.self, forKey: .status)) ?? .scheduled
        statusDetail = try container.decodeIfPresent(String.self, forKey: .statusDetail)
        retryAt = try container.decodeIfPresent(Date.self, forKey: .retryAt)
        resumeSessionId = try container.decodeIfPresent(String.self, forKey: .resumeSessionId)
        nextPrompt = try container.decodeIfPresent(String.self, forKey: .nextPrompt)
        nextAttachments = try container.decodeIfPresent([Attachment].self, forKey: .nextAttachments) ?? []
        archivedAttachments = try container.decodeIfPresent([Attachment].self, forKey: .archivedAttachments) ?? []
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        runs = try container.decodeIfPresent([RunRecord].self, forKey: .runs) ?? []
    }
}

extension RunRecord {
    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, outcome, sessionId, isResume, costUSD, inputTokens, outputTokens, numTurns, summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        outcome = try? container.decodeIfPresent(RunOutcome.self, forKey: .outcome)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        isResume = try container.decodeIfPresent(Bool.self, forKey: .isResume) ?? false
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        numTurns = try container.decodeIfPresent(Int.self, forKey: .numTurns)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
    }
}
