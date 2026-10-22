import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultContinuePrompt = "A execução anterior foi interrompida porque o limite de uso foi atingido. Continue a tarefa exatamente de onde parou, sem refazer o que já foi concluído."

    static let modelOptions: [(value: String, label: String)] = [
        ("", "Padrão"),
        ("claude-fable-5-1", "Fable 5.1"),
        ("claude-opus-5-5", "Opus 5.5"),
        ("claude-sonnet-5-5", "Sonnet 5.5"),
        ("claude-haiku-5-5", "Haiku 5.5")
    ]

    static let effortOptions: [(value: String, label: String)] = [
        ("", "Padrão"),
        ("low", "Baixo"),
        ("medium", "Médio"),
        ("high", "Alto"),
        ("xhigh", "Muito alto"),
        ("max", "Máximo")
    ]

    private let defaults = UserDefaults.standard

    @Published var claudePath: String { didSet { defaults.set(claudePath, forKey: Key.claudePath) } }
    @Published var maxConcurrent: Int { didSet { defaults.set(maxConcurrent, forKey: Key.maxConcurrent) } }
    @Published var defaultModel: String { didSet { defaults.set(defaultModel, forKey: Key.defaultModel) } }
    @Published var defaultEffort: String { didSet { defaults.set(defaultEffort, forKey: Key.defaultEffort) } }
    @Published var extraArguments: String { didSet { defaults.set(extraArguments, forKey: Key.extraArguments) } }
    @Published var skipPermissions: Bool { didSet { defaults.set(skipPermissions, forKey: Key.skipPermissions) } }
    @Published var continuePrompt: String { didSet { defaults.set(continuePrompt, forKey: Key.continuePrompt) } }
    @Published var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published var showOnNonNotchScreens: Bool { didSet { defaults.set(showOnNonNotchScreens, forKey: Key.showOnNonNotchScreens) } }
    @Published var preventCloseWhileTyping: Bool { didSet { defaults.set(preventCloseWhileTyping, forKey: Key.preventCloseWhileTyping) } }
    @Published var recentDirectories: [String] { didSet { defaults.set(recentDirectories, forKey: Key.recentDirectories) } }
    @Published var showClaudeStatus: Bool { didSet { defaults.set(showClaudeStatus, forKey: Key.showClaudeStatus) } }
    @Published var spotifyEnabled: Bool { didSet { defaults.set(spotifyEnabled, forKey: Key.spotifyEnabled) } }
    @Published var showMusicInNotch: Bool { didSet { defaults.set(showMusicInNotch, forKey: Key.showMusicInNotch) } }
    @Published var mirrorEnabled: Bool { didSet { defaults.set(mirrorEnabled, forKey: Key.mirrorEnabled) } }

    private init() {
        defaults.register(defaults: [
            Key.claudePath: "",
            Key.maxConcurrent: 1,
            Key.defaultModel: "",
            Key.defaultEffort: "",
            Key.extraArguments: "",
            Key.skipPermissions: true,
            Key.continuePrompt: AppSettings.defaultContinuePrompt,
            Key.openOnHover: true,
            Key.hapticsEnabled: true,
            Key.notificationsEnabled: true,
            Key.showOnNonNotchScreens: true,
            Key.preventCloseWhileTyping: true,
            Key.recentDirectories: [String](),
            Key.showClaudeStatus: true,
            Key.spotifyEnabled: true,
            Key.showMusicInNotch: true,
            Key.mirrorEnabled: true
        ])
        claudePath = defaults.string(forKey: Key.claudePath) ?? ""
        maxConcurrent = max(1, defaults.integer(forKey: Key.maxConcurrent))
        let storedModel = defaults.string(forKey: Key.defaultModel) ?? ""
        defaultModel = AppSettings.modelOptions.contains { $0.value == storedModel } ? storedModel : ""
        defaultEffort = defaults.string(forKey: Key.defaultEffort) ?? ""
        extraArguments = defaults.string(forKey: Key.extraArguments) ?? ""
        skipPermissions = defaults.bool(forKey: Key.skipPermissions)
        continuePrompt = defaults.string(forKey: Key.continuePrompt) ?? AppSettings.defaultContinuePrompt
        openOnHover = defaults.bool(forKey: Key.openOnHover)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        showOnNonNotchScreens = defaults.bool(forKey: Key.showOnNonNotchScreens)
        preventCloseWhileTyping = defaults.bool(forKey: Key.preventCloseWhileTyping)
        recentDirectories = defaults.stringArray(forKey: Key.recentDirectories) ?? []
        showClaudeStatus = defaults.bool(forKey: Key.showClaudeStatus)
        spotifyEnabled = defaults.bool(forKey: Key.spotifyEnabled)
        showMusicInNotch = defaults.bool(forKey: Key.showMusicInNotch)
        mirrorEnabled = defaults.bool(forKey: Key.mirrorEnabled)
    }

    func rememberDirectory(_ path: String) {
        var list = recentDirectories.filter { $0 != path }
        list.insert(path, at: 0)
        recentDirectories = Array(list.prefix(8))
    }

    var effectiveContinuePrompt: String {
        let trimmed = continuePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppSettings.defaultContinuePrompt : trimmed
    }

    private enum Key {
        static let claudePath = "claudePath"
        static let maxConcurrent = "maxConcurrent"
        static let defaultModel = "defaultModel"
        static let defaultEffort = "defaultEffort"
        static let extraArguments = "extraArguments"
        static let skipPermissions = "skipPermissions"
        static let continuePrompt = "continuePrompt"
        static let openOnHover = "openOnHover"
        static let hapticsEnabled = "hapticsEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let showOnNonNotchScreens = "showOnNonNotchScreens"
        static let preventCloseWhileTyping = "preventCloseWhileTyping"
        static let recentDirectories = "recentDirectories"
        static let showClaudeStatus = "showClaudeStatus"
        static let spotifyEnabled = "spotifyEnabled"
        static let showMusicInNotch = "showMusicInNotch"
        static let mirrorEnabled = "mirrorEnabled"
    }
}
