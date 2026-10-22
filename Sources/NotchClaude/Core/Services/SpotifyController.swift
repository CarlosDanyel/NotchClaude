import AppKit
import Combine
import OSLog

struct SpotifyTrack: Equatable {
    var id: String
    var name: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkURL: URL?
}

struct SpotifyState: Equatable {
    var isPlaying: Bool
    var track: SpotifyTrack?
    var position: TimeInterval
    var volume: Double?
}

@MainActor
final class SpotifyController: NSObject, ObservableObject {
    nonisolated static let bundleIdentifier = "com.spotify.client"
    private static let playbackNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")
    private nonisolated static let separator = "\u{1E}"

    private static let statusScript = """
    if application id "com.spotify.client" is not running then return ""
    with timeout of 3 seconds
        tell application id "com.spotify.client"
            set playerState to player state as text
            if playerState is "stopped" then return "stopped"
            set t to current track
            set sep to character id 30
            return playerState & sep & (id of t) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as text) & sep & ((player position) as text) & sep & (artwork url of t) & sep & (sound volume as text)
        end tell
    end timeout
    """

    @Published private(set) var isRunning = false
    @Published private(set) var isPlaying = false
    @Published private(set) var track: SpotifyTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var volume: Double?
    @Published private(set) var automationDenied = false

    private var enabled = false
    private var position: TimeInterval = 0
    private var positionDate = Date()
    private var artworkURL: URL?
    private var volumeTarget: Int?
    private var sendingVolume = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "app.notchclaude.spotify")
    private let log = Logger(subsystem: "app.notchclaude.NotchClaude", category: "spotify")

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    func position(at date: Date) -> TimeInterval {
        guard let track else { return 0 }
        let value = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        return min(max(0, value), track.duration)
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        value ? startObserving() : stopObserving()
    }

    func refresh(retries: Int = 0) {
        guard enabled, isRunning else { return }
        run(Self.statusScript) { [weak self] output in
            guard let self else { return }
            guard let output else {
                if retries > 0, !self.automationDenied {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.refresh(retries: retries - 1) }
                }
                return
            }
            if let state = Self.state(fromScript: output) { self.apply(state, authoritative: true) }
        }
    }

    func playPause() {
        guard isRunning else { return openApp() }
        if track != nil {
            position = position(at: Date())
            positionDate = Date()
            isPlaying.toggle()
        }
        command("playpause")
    }

    func seek(to seconds: TimeInterval) {
        guard let track else { return }
        position = min(max(0, seconds), track.duration)
        positionDate = Date()
        objectWillChange.send()
        command(String(format: "set player position to %.1f", position))
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        volumeTarget = Int((clamped * 100).rounded())
        sendVolume()
    }

    func next() { command("next track") }

    func previous() { command("previous track") }

    func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }


    nonisolated static func state(fromNotification info: [AnyHashable: Any]) -> SpotifyState? {
        guard let player = info["Player State"] as? String else { return nil }
        guard player != "Stopped", let id = info["Track ID"] as? String else {
            return SpotifyState(isPlaying: false, track: nil, position: 0)
        }
        let duration = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        let track = SpotifyTrack(
            id: id,
            name: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: duration / 1000,
            artworkURL: nil
        )
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        return SpotifyState(isPlaying: player == "Playing", track: track, position: position)
    }

    nonisolated static func state(fromScript output: String) -> SpotifyState? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let fields = text.components(separatedBy: separator)
        guard fields.count >= 8 else { return SpotifyState(isPlaying: false, track: nil, position: 0) }
        let artwork = fields[7].trimmingCharacters(in: .whitespaces)
        let track = SpotifyTrack(
            id: fields[1],
            name: fields[2],
            artist: fields[3],
            album: fields[4],
            duration: number(fields[5]) / 1000,
            artworkURL: artwork.isEmpty ? nil : URL(string: artwork)
        )
        let volume = fields.count > 8 ? number(fields[8]) / 100 : nil
        return SpotifyState(isPlaying: fields[0] == "playing", track: track, position: number(fields[6]), volume: volume)
    }

    // O AppleScript formata números no idioma do Mac ("12,5" em português).
    private nonisolated static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }


    private func startObserving() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playbackChanged(_:)),
            name: Self.playbackNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard Self.isSpotify(note) else { return }
                MainActor.assumeIsolated {
                    self?.isRunning = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.refresh(retries: 3) }
                }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard Self.isSpotify(note) else { return }
                MainActor.assumeIsolated { self?.reset() }
            }
        ]
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
        refresh(retries: 3)
    }

    private func stopObserving() {
        DistributedNotificationCenter.default().removeObserver(self, name: Self.playbackNotification, object: nil)
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        reset()
    }

    private nonisolated static func isSpotify(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleIdentifier
    }

    @objc private func playbackChanged(_ note: Notification) {
        guard enabled, let info = note.userInfo, let state = Self.state(fromNotification: info) else { return }
        log.debug("Notificação do Spotify: \(state.isPlaying ? "tocando" : "parado", privacy: .public)")
        isRunning = true
        apply(state, authoritative: false)
        if state.track != nil, !automationDenied { refresh() }
    }

    // A notificação não traz a capa; ela só muda quando a leitura vem do AppleScript, para não piscar.
    private func apply(_ state: SpotifyState, authoritative: Bool) {
        var next = state.track
        if !authoritative, next?.id == track?.id { next?.artworkURL = track?.artworkURL }
        if next != track { track = next }
        if state.isPlaying != isPlaying { isPlaying = state.isPlaying }
        if let value = state.volume, volumeTarget == nil, !sendingVolume, value != volume { volume = value }
        position = state.position
        positionDate = Date()
        if authoritative || next == nil { loadArtwork(next?.artworkURL) }
    }

    private func reset() {
        isRunning = false
        isPlaying = false
        track = nil
        loadArtwork(nil)
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        guard let url else {
            artwork = nil
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.artworkURL == url else { return }
                self.artwork = image
            }
        }.resume()
    }


    private func command(_ verb: String, completion: @escaping (String?) -> Void = { _ in }) {
        guard isRunning else { return completion(nil) }
        run("tell application id \"com.spotify.client\" to \(verb)", completion: completion)
    }

    // Arrastar o volume gera muitos valores: manda um por vez e sempre o mais recente.
    // O Spotify guarda um ponto a menos do que recebe (37 vira 36), por isso o +1.
    private func sendVolume() {
        guard !sendingVolume, let target = volumeTarget else { return }
        volumeTarget = nil
        sendingVolume = true
        let value = target > 0 && target < 100 ? target + 1 : target
        command("set sound volume to \(value)") { [weak self] _ in
            guard let self else { return }
            self.sendingVolume = false
            self.sendVolume()
        }
    }

    private func run(_ script: String, completion: @escaping (String?) -> Void) {
        queue.async {
            let result = Self.execute(script)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let output):
                    self.automationDenied = false
                    completion(output)
                case .failure(let error):
                    self.log.error("AppleScript do Spotify falhou: \(error.message, privacy: .public)")
                    if error.isAutomationDenied { self.automationDenied = true }
                    completion(nil)
                }
            }
        }
    }

    private struct ScriptError: Error {
        var message: String
        var isAutomationDenied: Bool { message.contains("-1743") }
    }

    private nonisolated static func execute(_ script: String) -> Result<String, ScriptError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return .failure(ScriptError(message: error.localizedDescription))
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return .failure(ScriptError(message: String(decoding: errorData, as: UTF8.self)))
        }
        return .success(String(decoding: data, as: UTF8.self))
    }
}
