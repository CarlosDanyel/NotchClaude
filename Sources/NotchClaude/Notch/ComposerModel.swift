import Foundation
import Combine

@MainActor
final class ComposerModel: ObservableObject {
    enum When: Equatable {
        case now
        case at
    }

    @Published var directory: String
    @Published var prompt = ""
    @Published var attachments: [Attachment] = []
    @Published var when: When = .now
    @Published var date: Date = ComposerModel.roundedDate(Date().addingTimeInterval(3600))
    @Published var repeatRule: RepeatRule = .never
    @Published var model: String
    @Published var effort: String
    @Published private(set) var context = ProjectContext()

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        directory = settings.recentDirectories.first ?? FileManager.default.homeDirectoryForCurrentUser.path
        model = settings.defaultModel
        effort = settings.defaultEffort
        refreshContext()
    }

    var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSubmit: Bool { !trimmedPrompt.isEmpty && !directory.isEmpty }

    var directoryName: String { URL(fileURLWithPath: directory).lastPathComponent }

    func setDirectory(_ path: String) {
        directory = path
        settings.rememberDirectory(path)
        refreshContext()
    }

    func refreshContext() {
        let path = directory
        DispatchQueue.global(qos: .userInitiated).async {
            let context = ProjectInspector.inspect(path)
            DispatchQueue.main.async {
                guard self.directory == path else { return }
                self.context = context
            }
        }
    }

    func add(_ items: [Attachment]) {
        attachments.append(contentsOf: items)
    }

    func remove(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
        AttachmentImporter.remove([attachment])
    }

    func insert(_ skill: SkillInfo) {
        let token = "/\(skill.name) "
        if prompt.isEmpty || prompt.hasSuffix(" ") || prompt.hasSuffix("\n") {
            prompt += token
        } else {
            prompt += " " + token
        }
    }

    func setDelay(_ interval: TimeInterval) {
        when = .at
        date = Date().addingTimeInterval(interval)
    }

    func setTomorrow(hour: Int) {
        when = .at
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    func makeTask() -> ClaudeTask? {
        guard canSubmit else { return nil }
        let start = when == .now ? Date() : max(date, Date())
        settings.rememberDirectory(directory)
        return ClaudeTask(
            title: ClaudeTask.makeTitle(from: trimmedPrompt),
            prompt: trimmedPrompt,
            directory: directory,
            attachments: attachments,
            model: model.isEmpty ? nil : model,
            effort: effort.isEmpty ? nil : effort,
            scheduledAt: start,
            anchorDate: start,
            repeatRule: repeatRule,
            status: when == .now ? .queued : .scheduled,
            statusDetail: when == .now ? "Na fila" : nil
        )
    }

    func reset() {
        prompt = ""
        attachments = []
        when = .now
        repeatRule = .never
        date = Self.roundedDate(Date().addingTimeInterval(3600))
    }

    private static func roundedDate(_ date: Date) -> Date {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        parts.minute = ((parts.minute ?? 0) / 15) * 15
        return calendar.date(from: parts) ?? date
    }
}
