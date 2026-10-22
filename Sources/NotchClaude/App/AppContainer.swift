import AppKit
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let settings = AppSettings.shared
    let shell = ShellEnvironment.shared
    let store: TaskStore
    let runs: RunManager
    let scheduler: Scheduler
    let composer: ComposerModel
    let notifier = Notifier()
    lazy var router = WindowRouter(container: self)
    lazy var notch = NotchController(container: self)

    init() {
        store = TaskStore()
        runs = RunManager(store: store, settings: settings, shell: shell)
        scheduler = Scheduler(store: store, runs: runs, settings: settings)
        composer = ComposerModel(settings: settings)
    }

    func start() {
        store.recoverInterruptedTasks(continuePrompt: settings.effectiveContinuePrompt)
        store.purgeOrphanAttachments()
        runs.onCompletion = { [weak self] task, completion in self?.handleCompletion(task, completion) }
        notifier.onOpenTask = { [weak self] id in self?.router.showMonitor(id) }
        notifier.activate()
        notch.install()
        shell.refresh { [weak self] in self?.scheduler.start() }
        LaunchAtLogin.synchronize()
    }

    func shutdown() {
        runs.stopAll()
    }

    func submitComposer() -> Bool {
        guard let task = composer.makeTask() else { return false }
        store.add(task)
        composer.reset()
        scheduler.tick()
        return true
    }

    func handle(url: URL) {
        guard url.scheme == "notchclaude" else { return }
        let argument = url.pathComponents.dropFirst().first
        switch url.host {
        case "new":
            if let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "dir" })?.value {
                composer.setDirectory((path as NSString).expandingTildeInPath)
            }
            notch.open(page: .compose)
        case "task":
            if let argument, let id = UUID(uuidString: argument) { router.showMonitor(id) }
        case "settings":
            router.showSettings()
        default:
            notch.open(page: .tasks)
        }
    }

    func delete(_ taskId: UUID) {
        if runs.isRunning(taskId) { runs.stop(taskId) }
        router.closeMonitor(taskId)
        store.remove(taskId)
    }

    func duplicate(_ taskId: UUID) {
        guard let task = store.task(taskId) else { return }
        composer.setDirectory(task.directory)
        composer.prompt = task.prompt
        composer.model = task.model ?? ""
        composer.effort = task.effort ?? ""
        composer.repeatRule = task.repeatRule
        composer.add(AttachmentImporter.importFiles(task.attachments.map(\.url)))
        notch.open(page: .compose)
    }

    private func handleCompletion(_ task: ClaudeTask, _ completion: RunCompletion) {
        let peek: NotchPeek
        let title: String
        switch completion.outcome {
        case .success:
            title = "Tarefa concluída"
            peek = NotchPeek(symbol: "checkmark.circle.fill", tint: Theme.success, title: title, subtitle: task.title)
        case .rateLimited:
            title = "Tokens esgotados"
            peek = NotchPeek(symbol: "gauge.with.needle.fill", tint: Theme.danger, title: title, subtitle: task.statusDetail ?? task.title)
        case .cancelled:
            title = "Tarefa interrompida"
            peek = NotchPeek(symbol: "stop.circle.fill", tint: Theme.secondaryText, title: title, subtitle: task.title)
        case .failed, .interrupted:
            title = "Tarefa falhou"
            peek = NotchPeek(symbol: "exclamationmark.octagon.fill", tint: Theme.danger, title: title, subtitle: task.title)
        }
        notch.showPeek(peek)
        if settings.notificationsEnabled, completion.outcome != .cancelled {
            let body = completion.outcome == .rateLimited ? "\(task.title)\n\(task.statusDetail ?? "")" : task.title
            notifier.post(title: title, body: body, taskId: task.id)
        }
    }
}
