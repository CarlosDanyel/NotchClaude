import Foundation
import Combine

struct RunCompletion {
    var outcome: RunOutcome
    var limitHit: RateLimitHit?
    var result: ResultInfo?
    var sessionId: String?
    var madeProgress: Bool
    var summary: String?
}

@MainActor
final class RunSession: ObservableObject, Identifiable {
    let id: UUID
    let taskId: UUID
    let startedAt = Date()

    @Published private(set) var items: [TranscriptItem] = []
    @Published private(set) var liveText = ""
    @Published private(set) var activity = "Iniciando Claude…"
    @Published private(set) var isRunning = true

    var onUsage: ((UsageSnapshot) -> Void)?
    var onFinish: ((RunSession, RunCompletion) -> Void)?

    private var builder = TranscriptBuilder()
    private let process: ClaudeProcess
    private let header: [String: Any]
    private var cancelled = false
    private var sleepActivity: NSObjectProtocol?

    init(taskId: UUID, runId: UUID, launch: ClaudeLaunch, logURL: URL) {
        self.id = runId
        self.taskId = taskId
        self.header = launch.header
        self.process = ClaudeProcess(launch: launch, logURL: logURL)
    }

    func start() throws {
        process.onEvent = { [weak self] object in self?.apply(object) }
        process.onExit = { [weak self] object in self?.complete(exit: object) }
        try process.start()
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "NotchClaude executando uma tarefa do Claude"
        )
        apply(header)
    }

    func stop() {
        cancelled = true
        activity = "Interrompendo…"
        process.stop()
    }

    private func apply(_ object: [String: Any]) {
        let previousCount = builder.items.count
        if let usage = builder.consume(object) { onUsage?(usage) }
        let type = object["type"] as? String
        if type != "stream_event" || builder.items.count != previousCount {
            items = builder.items
        }
        if liveText != builder.liveText { liveText = builder.liveText }
        if activity != builder.activity, !cancelled { activity = builder.activity }
    }

    private func complete(exit: [String: Any]) {
        apply(exit)
        isRunning = false
        if let sleepActivity { ProcessInfo.processInfo.endActivity(sleepActivity) }
        sleepActivity = nil

        let stderr = exit["stderr"] as? String ?? ""
        let (outcome, hit) = builder.outcome(cancelled: cancelled, stderr: stderr)
        let summary: String?
        switch outcome {
        case .success: summary = builder.result?.text
        case .rateLimited: summary = builder.result?.text ?? builder.failureSummary
        default: summary = builder.failureSummary ?? builder.result?.text
        }
        activity = outcome == .success ? "Concluído" : outcome == .cancelled ? "Interrompido" : outcome == .rateLimited ? "Tokens esgotados" : "Falhou"

        onFinish?(self, RunCompletion(
            outcome: outcome,
            limitHit: hit,
            result: builder.result,
            sessionId: builder.sessionId,
            madeProgress: builder.madeProgress,
            summary: summary.map { String($0.prefix(600)) }
        ))
    }
}
