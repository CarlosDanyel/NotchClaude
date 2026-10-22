import Foundation
import Combine

@MainActor
final class RunManager: ObservableObject {
    @Published private(set) var sessions: [UUID: RunSession] = [:]

    var onCompletion: ((ClaudeTask, RunCompletion) -> Void)?

    private let store: TaskStore
    private let settings: AppSettings
    private let shell: ShellEnvironment
    private var finished: [UUID: RunSession] = [:]
    private var finishedOrder: [UUID] = []

    init(store: TaskStore, settings: AppSettings, shell: ShellEnvironment) {
        self.store = store
        self.settings = settings
        self.shell = shell
    }

    var runningCount: Int { sessions.count }

    func isRunning(_ taskId: UUID) -> Bool { sessions[taskId] != nil }

    func liveSession(for taskId: UUID) -> RunSession? { sessions[taskId] }

    func session(forRun runId: UUID) -> RunSession? {
        sessions.values.first { $0.id == runId } ?? finished[runId]
    }

    func start(_ taskId: UUID) {
        guard sessions[taskId] == nil, let task = store.task(taskId) else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: task.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            markFailed(taskId, "A pasta \(task.directory) não existe")
            return
        }
        guard let executable = shell.claudeExecutable(override: settings.claudePath) else {
            markFailed(taskId, "Claude Code não encontrado. Defina o caminho em Ajustes.")
            return
        }

        let plan = RunPlan(task: task, settings: settings)
        let launch: ClaudeLaunch
        do {
            launch = try ClaudeCommandBuilder.launch(plan: plan, settings: settings, executable: executable, environment: shell.environment)
        } catch {
            markFailed(taskId, error.localizedDescription)
            return
        }

        let run = RunRecord(sessionId: plan.sessionId, isResume: plan.isResume)
        let session = RunSession(taskId: taskId, runId: run.id, launch: launch, logURL: run.logURL)
        session.onUsage = { [weak self] usage in self?.store.updateUsage(usage) }
        session.onFinish = { [weak self] session, completion in self?.finish(session, completion) }

        store.update(taskId) { task in
            task.status = .running
            task.statusDetail = plan.isResume ? "Continuando sessão" : nil
            task.retryAt = nil
            task.runs.append(run)
        }
        sessions[taskId] = session

        do {
            try session.start()
        } catch {
            sessions[taskId] = nil
            store.updateRun(taskId: taskId, runId: run.id) { record in
                record.endedAt = Date()
                record.outcome = .failed
                record.summary = error.localizedDescription
            }
            markFailed(taskId, "Não foi possível iniciar o Claude: \(error.localizedDescription)")
        }
    }

    func stop(_ taskId: UUID) {
        sessions[taskId]?.stop()
    }

    func stopAll() {
        sessions.values.forEach { $0.stop() }
    }

    private func markFailed(_ taskId: UUID, _ message: String) {
        store.update(taskId) { task in
            task.status = .failed
            task.statusDetail = message
            task.finishedAt = Date()
        }
        if let task = store.task(taskId) {
            onCompletion?(task, RunCompletion(outcome: .failed, madeProgress: false, summary: message))
        }
    }

    private func finish(_ session: RunSession, _ completion: RunCompletion) {
        let taskId = session.taskId
        sessions[taskId] = nil
        retain(session)

        let now = Date()
        store.updateRun(taskId: taskId, runId: session.id) { record in
            record.endedAt = now
            record.outcome = completion.outcome
            record.costUSD = completion.result?.costUSD
            record.inputTokens = completion.result?.inputTokens
            record.outputTokens = completion.result?.outputTokens
            record.numTurns = completion.result?.numTurns
            record.summary = completion.summary
            if let sessionId = completion.sessionId { record.sessionId = sessionId }
        }

        if completion.outcome == .rateLimited {
            let hit = completion.limitHit
            let fallback: TimeInterval = hit?.kind == "throttle" ? 300 : 900
            let resetsAt = max(hit?.resetsAt ?? now.addingTimeInterval(fallback), now.addingTimeInterval(60))
            store.registerLimit(until: resetsAt.addingTimeInterval(30), kind: hit?.kind)
        }

        let limit = store.limit
        let continuePrompt = settings.effectiveContinuePrompt

        store.update(taskId) { task in
            let sessionId = completion.sessionId ?? task.lastSessionId
            switch completion.outcome {
            case .success:
                task.clearPendingResume()
                task.finishedAt = now
                if let next = task.repeatRule.nextDate(after: now, anchor: task.anchorDate) {
                    task.status = .scheduled
                    task.scheduledAt = next
                    task.statusDetail = "Última execução concluída"
                } else {
                    task.status = .completed
                    task.statusDetail = completion.summary.map(Self.firstLine)
                }
            case .rateLimited:
                task.status = .rateLimited
                task.retryAt = limit.blockedUntil
                task.statusDetail = Self.limitDetail(limit)
                if completion.madeProgress, let sessionId {
                    task.archivedAttachments += task.nextAttachments
                    task.nextAttachments = []
                    task.resumeSessionId = sessionId
                    task.nextPrompt = continuePrompt
                }
            case .failed, .interrupted:
                task.clearPendingResume()
                task.finishedAt = now
                if let next = task.repeatRule.nextDate(after: now, anchor: task.anchorDate) {
                    task.status = .scheduled
                    task.scheduledAt = next
                    task.statusDetail = "Última execução falhou"
                } else {
                    task.status = .failed
                    task.statusDetail = completion.summary.map(Self.firstLine) ?? "Falhou"
                }
            case .cancelled:
                task.clearPendingResume()
                task.finishedAt = now
                task.status = .cancelled
                task.statusDetail = "Interrompida por você"
            }
        }

        if let task = store.task(taskId) { onCompletion?(task, completion) }
    }

    private func retain(_ session: RunSession) {
        finished[session.id] = session
        finishedOrder.append(session.id)
        while finishedOrder.count > 12 {
            finished[finishedOrder.removeFirst()] = nil
        }
    }

    static func limitDetail(_ limit: LimitState) -> String {
        guard let until = limit.blockedUntil else { return limit.kindLabel }
        return "\(limit.kindLabel) · libera \(Formatters.resetDescription(until))"
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.prefix(140))
    }
}
