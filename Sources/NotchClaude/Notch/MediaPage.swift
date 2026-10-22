import SwiftUI
import AVFoundation

struct MediaPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            if settings.spotifyEnabled {
                SpotifyCard()
            }
            if settings.mirrorEnabled {
                MirrorCard()
                    .frame(width: settings.spotifyEnabled ? 260 : nil)
            }
        }
    }
}

struct SpotifyCard: View {
    @EnvironmentObject private var spotify: SpotifyController
    @State private var scrubbing: TimeInterval?

    var body: some View {
        Group {
            if let track = spotify.track {
                player(track)
            } else {
                placeholder
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .onAppear { spotify.refresh() }
    }

    private func player(_ track: SpotifyTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ArtworkView(image: spotify.artwork, size: 104, radius: 12)
                    .onTapGesture { spotify.openApp() }
                    .help("Abrir o Spotify")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        EqualizerBars(animating: spotify.isPlaying, height: 10)
                        Text(spotify.isPlaying ? "Tocando no Spotify" : "Pausado")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.spotify)
                    }
                    .padding(.bottom, 4)
                    Text(track.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    Text(track.album)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            progress(track)
            controls
        }
    }

    private func progress(_ track: SpotifyTrack) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = spotify.position(at: context.date)
            HStack(spacing: 8) {
                Text(Formatters.trackTime(scrubbing ?? position))
                    .frame(width: 30, alignment: .leading)
                ScrubBar(
                    value: track.duration > 0 ? position / track.duration : 0,
                    onChanged: { scrubbing = $0 * track.duration },
                    onCommit: { fraction in
                        spotify.seek(to: fraction * track.duration)
                        scrubbing = nil
                    }
                )
                .allowsHitTesting(!spotify.automationDenied)
                .help("Arraste para avançar ou voltar")
                Text(Formatters.trackTime(track.duration))
                    .frame(width: 30, alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var volumeSymbol: String {
        let value = spotify.volume ?? 0
        if value == 0 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.wave.1.fill" }
        if value < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    @ViewBuilder
    private var controls: some View {
        if spotify.automationDenied {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                Text("Permita o controle do Spotify para usar os botões")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Permitir") { PrivacyPane.automation.open() }
                    .buttonStyle(PillButtonStyle(tint: Theme.warning, prominent: false))
            }
        } else {
            HStack(spacing: 10) {
                NotchIconButton(symbol: "backward.fill", help: "Anterior", size: 30) { spotify.previous() }
                NotchIconButton(symbol: spotify.isPlaying ? "pause.fill" : "play.fill", help: spotify.isPlaying ? "Pausar" : "Tocar", size: 36) {
                    spotify.playPause()
                }
                NotchIconButton(symbol: "forward.fill", help: "Próxima", size: 30) { spotify.next() }
                Spacer(minLength: 12)
                Image(systemName: volumeSymbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 18)
                ScrubBar(value: spotify.volume ?? 0, onChanged: spotify.setVolume, onCommit: spotify.setVolume)
                    .frame(width: 76)
                    .opacity(spotify.volume == nil ? 0.4 : 1)
                    .allowsHitTesting(spotify.volume != nil)
                    .help("Volume do Spotify")
            }
        }
    }

    private var placeholder: some View {
        let installed = spotify.isInstalled
        return VStack(alignment: .leading, spacing: 8) {
            ArtworkView(image: nil, size: 44, radius: 10)
            Text(!installed ? "Spotify não encontrado" : (spotify.isRunning ? "Nada tocando" : "Spotify fechado"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Text(!installed
                 ? "Instale o Spotify para ver e controlar a música por aqui."
                 : (spotify.isRunning ? "Dê play no Spotify ou aqui mesmo." : "Abra o Spotify e a música que estiver tocando aparece aqui e no notch."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if installed {
                Button(spotify.isRunning ? "Tocar" : "Abrir Spotify") {
                    spotify.isRunning ? spotify.playPause() : spotify.openApp()
                }
                .buttonStyle(PillButtonStyle(tint: Theme.spotify))
            }
        }
    }
}

struct MirrorCard: View {
    @EnvironmentObject private var mirror: CameraMirror

    var body: some View {
        ZStack {
            if mirror.isOn {
                if let layer = mirror.previewLayer {
                    CameraPreview(layer: layer)
                }
                if mirror.state == .starting {
                    ProgressView().controlSize(.small)
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottom) {
            if mirror.isOn {
                Button { mirror.stop() } label: {
                    Label("Desligar", systemImage: "video.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mirror.state)
    }

    private var placeholder: some View {
        let content: (symbol: String, title: String, message: String, button: String)
        switch mirror.state {
        case .denied:
            content = ("video.slash.fill", "Sem acesso à câmera", "Libere o NotchClaude em Ajustes do Sistema › Privacidade › Câmera.", "Abrir Ajustes")
        case .unavailable:
            content = ("video.slash", "Câmera indisponível", "Conecte uma câmera ou feche o app que estiver usando ela.", "Tentar de novo")
        default:
            content = ("camera.fill", "Espelho", "Veja como você está antes de entrar numa call.", "Ligar câmera")
        }
        return VStack(spacing: 8) {
            Image(systemName: content.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(mirror.state == .off ? Theme.accent : Theme.warning)
            Text(content.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(content.message)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(content.button) {
                mirror.state == .denied ? PrivacyPane.camera.open() : mirror.start()
            }
            .buttonStyle(PillButtonStyle())
            .padding(.top, 2)
        }
        .padding(16)
    }
}

struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(previewLayer: layer)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            wantsLayer = true
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            fitLayer()
        }

        override func layout() {
            super.layout()
            fitLayer()
        }

        private func fitLayer() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
