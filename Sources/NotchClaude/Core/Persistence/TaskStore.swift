import Foundation
import Combine

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [ClaudeTask] = []
    @Published private(set) var limit = LimitState()
    @Published private(set) var usage: UsageSnapshot?

    private struct Snapshot: Codable {
        var tasks: [ClaudeTask]
        var limit: LimitState
        var usage: UsageSnapshot?
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        AppPaths.prepare()
        load()
    }

    func task(_ id: UUID) -> ClaudeTask? {
        tasks.first { $0.id == id }
    }

    func add(_ task: ClaudeTask) {
        tasks.append(task)
        save()
    }

    func update(_ id: UUID, _ change: (inout ClaudeTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        save()
    }

    func updateRun(taskId: UUID, runId: UUID, _ change: (inout RunRecord) -> Void) {
        update(taskId) { task in
            guard let index = task.runs.firstIndex(where: { $0.id == runId }) else { return }
            change(&task.runs[index])
        }
    }

    func remove(_ id: UUID) {
        guard let task = task(id) else { return }
        let fileManager = FileManager.default
        task.allAttachments.forEach { try? fileManager.removeItem(at: $0.url) }
        task.runs.forEach { try? fileManager.removeItem(at: $0.logURL) }
        tasks.removeAll { $0.id == id }
        save()
    }

    func removeFinished() {
        tasks.filter { $0.status.isFinished && $0.repeatRule == .never }.forEach { remove($0.id) }
    }

    func registerLimit(until date: Date, kind: String?) {
        let current = limit.blockedUntil ?? .distantPast
        limit = LimitState(blockedUntil: max(current, date), kind: kind ?? limit.kind, detectedAt: Date())
        save()
    }

    func clearLimit() {
        guard limit.blockedUntil != nil else { return }
        limit = LimitState()
        save()
    }

    func updateUsage(_ snapshot: UsageSnapshot) {
        usage = snapshot
        save()
    }

    func recoverInterruptedTasks(continuePrompt: String) {
        var changed = false
        for index in tasks.indices where tasks[index].status == .running {
            changed = true
            var task = tasks[index]
            if let runIndex = task.runs.indices.last {
                task.runs[runIndex].outcome = .interrupted
                task.runs[runIndex].endedAt = task.runs[runIndex].endedAt ?? Date()
                if TranscriptLoader.containsModelOutput(task.runs[runIndex].logURL) {
                    task.resumeSessionId = task.runs[runIndex].sessionId
                    task.nextPrompt = continuePrompt
                    task.nextAttachments = []
                }
            }
            task.status = .queued
            task.statusDetail = "Retomando após o app ser encerrado"
            tasks[index] = task
        }
        if changed { save() }
    }

    func purgeOrphanAttachments() {
        let referenced = Set(tasks.flatMap { $0.allAttachments.map(\.fileName) })
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.attachments, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let threshold = Date().addingTimeInterval(-86_400)
        for file in files where !referenced.contains(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < threshold { try? fileManager.removeItem(at: file) }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.storeFile),
              let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return }
        tasks = snapshot.tasks
        limit = snapshot.limit
        usage = snapshot.usage
    }

    private func save() {
        let snapshot = Snapshot(tasks: tasks, limit: limit, usage: usage)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: AppPaths.storeFile, options: .atomic)
    }
}
