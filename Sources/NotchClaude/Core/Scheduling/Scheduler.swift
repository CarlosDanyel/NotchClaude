import AppKit

@MainActor
final class Scheduler {
    private let store: TaskStore
    private let runs: RunManager
    private let settings: AppSettings
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(store: TaskStore, runs: RunManager, settings: AppSettings) {
        self.store = store
        self.runs = runs
        self.settings = settings
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.5
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        tick()
    }

    func runNow(_ taskId: UUID) {
        store.clearLimit()
        store.update(taskId) { task in
            task.status = .queued
            task.scheduledAt = Date()
            task.retryAt = nil
            task.statusDetail = "Na fila"
        }
        tick()
    }

    func retry(_ taskId: UUID) {
        store.update(taskId) { task in
            task.clearPendingResume()
            task.finishedAt = nil
        }
        runNow(taskId)
    }

    func continueTask(_ taskId: UUID, prompt: String, attachments: [Attachment]) {
        store.update(taskId) { task in
            guard let sessionId = task.lastSessionId else { return }
            task.archivedAttachments += task.nextAttachments
            task.resumeSessionId = sessionId
            task.nextPrompt = prompt
            task.nextAttachments = attachments
            task.status = .queued
            task.scheduledAt = Date()
            task.retryAt = nil
            task.finishedAt = nil
            task.statusDetail = "Mensagem enviada"
        }
        tick()
    }

    func cancel(_ taskId: UUID) {
        if runs.isRunning(taskId) {
            runs.stop(taskId)
            return
        }
        store.update(taskId) { task in
            guard task.status.isPending else { return }
            task.status = .cancelled
            task.statusDetail = "Cancelada por você"
            task.finishedAt = Date()
        }
    }

    func tick() {
        let now = Date()
        if let until = store.limit.blockedUntil, now >= until { store.clearLimit() }
        let limit = store.limit
        let blocked = limit.isBlocked(at: now)

        for task in store.tasks where task.status.isPending && !runs.isRunning(task.id) {
            let due = task.scheduledAt <= now
            if !due {
                if task.status != .scheduled {
                    store.update(task.id) { $0.status = .scheduled }
                }
                continue
            }
            if blocked {
                let detail = RunManager.limitDetail(limit)
                if task.status != .rateLimited || task.retryAt != limit.blockedUntil || task.statusDetail != detail {
                    store.update(task.id) { item in
                        item.status = .rateLimited
                        item.retryAt = limit.blockedUntil
                        item.statusDetail = detail
                    }
                }
                continue
            }
            if let retryAt = task.retryAt, retryAt > now { continue }
            if task.status != .queued {
                let released = task.status == .rateLimited
                store.update(task.id) { item in
                    item.status = .queued
                    item.retryAt = nil
                    item.statusDetail = released ? "Tokens liberados · na fila" : "Na fila"
                }
            }
        }

        guard !blocked else { return }
        let available = settings.maxConcurrent - runs.runningCount
        guard available > 0 else { return }
        let candidates = store.tasks
            .filter { $0.status == .queued && !runs.isRunning($0.id) }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .prefix(available)
        candidates.forEach { runs.start($0.id) }
    }
}
