@preconcurrency import AVFoundation
import Combine
import OSLog

@MainActor
final class CameraMirror: ObservableObject {
    enum State: Equatable {
        case off
        case starting
        case running
        case denied
        case unavailable
    }

    @Published private(set) var state: State = .off

    let session = AVCaptureSession()

    // A camada fica sempre ligada à sessão: ligar/desligar a sessão enquanto o SwiftUI adiciona ou remove
    // uma camada de preview derruba o app ("Collection was mutated while being enumerated").
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    private let queue = DispatchQueue(label: "app.notchclaude.camera")
    private let log = Logger(subsystem: "app.notchclaude.NotchClaude", category: "camera")
    private var wanted = false

    var isOn: Bool { state == .starting || state == .running }

    func toggle() {
        isOn ? stop() : start()
    }

    func start() {
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            launch()
        case .notDetermined:
            state = .starting
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !granted {
                        self.wanted = false
                        self.state = .denied
                    } else if self.wanted {
                        self.launch()
                    } else {
                        self.state = .off
                    }
                }
            }
        default:
            wanted = false
            state = .denied
        }
    }

    func stop() {
        wanted = false
        guard state != .off else { return }
        state = .off
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func launch() {
        guard state != .running else { return }
        let session = session
        if previewLayer == nil { makePreviewLayer() }
        let log = log
        state = .starting
        queue.async {
            if session.inputs.isEmpty { Self.configure(session) }
            if session.inputs.isEmpty {
                log.error("Nenhuma câmera disponível")
            } else if !session.isRunning {
                session.startRunning()
            }
            let running = session.isRunning
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.wanted else {
                    self.queue.async { if session.isRunning { session.stopRunning() } }
                    return
                }
                if running { self.mirrorPreview() }
                self.state = running ? .running : .unavailable
            }
        }
    }

    private func makePreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
    }

    private func mirrorPreview() {
        guard let connection = previewLayer?.connection, connection.isVideoMirroringSupported, !connection.isVideoMirrored else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }

    private nonisolated static func configure(_ session: AVCaptureSession) {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
    }
}
