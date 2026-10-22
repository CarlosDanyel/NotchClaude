import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    let controller: NotchController

    var body: some View {
        let size = model.shapeSize
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .opacity(model.isShapeVisible ? 1 : 0)
                .shadow(color: .black.opacity(model.isOpen ? 0.6 : 0), radius: 22, y: 8)

            ZStack(alignment: .top) {
                if model.isOpen {
                    OpenNotchView(model: model, controller: controller)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).animation(.easeOut(duration: 0.28).delay(0.06)),
                            removal: .opacity.animation(.easeIn(duration: 0.08))
                        ))
                } else {
                    ClosedNotchView(model: model)
                        .transition(.opacity.animation(.easeOut(duration: 0.18)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture {
                if !model.isOpen { controller.open(sticky: false) }
            }
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $model.isDropTargeted) { providers in
                controller.handleDrop(providers)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

struct ClosedNotchView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .frame(width: model.wingWidth, alignment: .center)
                Spacer(minLength: model.geometry.notchSize.width)
                trailing
                    .frame(width: model.wingWidth, alignment: .center)
            }
            .padding(.horizontal, model.topRadius)
            .frame(height: model.geometry.notchSize.height)

            if let peek = model.peek {
                HStack(spacing: 8) {
                    Image(systemName: peek.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(peek.tint)
                    Text(peek.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(peek.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 22)
                .frame(height: 34)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if model.showsStatus {
            ClaudeStatusMark(status: model.status)
        } else if model.peek != nil || model.liveActivity != nil {
            switch model.liveActivity {
            case .running:
                ClaudeSpinner(size: 15)
            case .limited:
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            case .none:
                ClaudeSpinner(size: 15, animating: false)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if model.showsMusic {
            NowPlayingWing()
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
        } else {
            activityTrailing
        }
    }

    @ViewBuilder
    private var activityTrailing: some View {
        switch model.liveActivity {
        case .running(let count, let startedAt, _):
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.accent.opacity(0.2)))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Formatters.shortDuration(context.date.timeIntervalSince(startedAt)))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
        case .limited(let until, _):
            Text(Formatters.clock(until))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.danger)
        case .none:
            EmptyView()
        }
    }
}

struct NowPlayingWing: View {
    @EnvironmentObject private var spotify: SpotifyController

    var body: some View {
        HStack(spacing: 4) {
            ArtworkView(image: spotify.artwork, size: 20, radius: 5)
            EqualizerBars(animating: spotify.isPlaying, height: 11)
        }
        .help(spotify.track.map { "\($0.name) · \($0.artist)" } ?? "Spotify")
    }
}

struct OpenNotchView: View {
    @ObservedObject var model: NotchViewModel
    let controller: NotchController

    var body: some View {
        VStack(spacing: 0) {
            NotchHeaderView(model: model, controller: controller)
                .frame(height: model.geometry.notchSize.height)

            ZStack {
                switch model.page {
                case .tasks:
                    TasksPage(controller: controller)
                        .transition(.opacity.combined(with: .offset(x: -14)))
                case .compose:
                    ComposerPage(controller: controller)
                        .transition(.opacity.combined(with: .offset(x: 14)))
                case .media:
                    MediaPage()
                        .transition(.opacity.combined(with: .offset(x: 14)))
                }

                if model.isDraggingFiles || model.isDropTargeted {
                    DropZoneView(isTargeted: model.isDropTargeted)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, NotchViewModel.contentPadding)
            .padding(.top, 10)
            .padding(.bottom, NotchViewModel.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, model.topRadius)
        .animation(.easeInOut(duration: 0.2), value: model.isDraggingFiles)
        .animation(.easeInOut(duration: 0.2), value: model.isDropTargeted)
    }
}

struct DropZoneView: View {
    var isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    .foregroundStyle(isTargeted ? Theme.accent : Color.white.opacity(0.25))
            )
            .overlay(
                VStack(spacing: 10) {
                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(isTargeted ? Theme.accent : .white.opacity(0.7))
                        .scaleEffect(isTargeted ? 1.12 : 1)
                    Text("Solte para anexar à nova tarefa")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Imagens vão para o Claude como no chat · uma pasta vira o diretório de trabalho")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
    }
}
