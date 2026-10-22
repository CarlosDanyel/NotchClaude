import SwiftUI
import AppKit

struct NotchIconButton: View {
    var symbol: String
    var help: String
    var tint: Color = Theme.primaryText
    var size: CGFloat = 26
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint.opacity(hovering ? 1 : 0.8))
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? Theme.cardHover : Theme.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(prominent ? tint.opacity(configuration.isPressed ? 0.75 : 1) : tint.opacity(configuration.isPressed ? 0.22 : 0.14))
            )
            .contentShape(Capsule())
    }
}

struct ChipButton: View {
    var title: String
    var symbol: String?
    var selected = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Theme.primaryText.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule().fill(selected ? Theme.accent : (hovering ? Theme.cardHover : Theme.card))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct AttachmentThumbnail: View {
    var url: URL
    var name: String
    var isImage: Bool
    var size: CGFloat = 46
    var onRemove: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isImage, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: "doc.fill").font(.system(size: size * 0.3))
                        Text(url.pathExtension.uppercased()).font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.card)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.stroke))

            if let onRemove, hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.75))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }
        }
        .onHover { hovering = $0 }
        .help(name)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
    }
}

struct ScrubBar: View {
    var value: Double
    var tint: Color = .white
    var onChanged: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void

    @State private var dragValue: Double?
    @State private var hovering = false

    private var active: Bool { hovering || dragValue != nil }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let shown = min(max(dragValue ?? value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(tint).frame(width: max(3, width * shown))
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.4), radius: 1.5)
                    .offset(x: min(max(0, width * shown - 4), width - 8))
                    .opacity(active ? 1 : 0)
            }
            .frame(height: active ? 4 : 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        dragValue = fraction
                        onChanged(fraction)
                    }
                    .onEnded { gesture in
                        let fraction = min(max(gesture.location.x / width, 0), 1)
                        onCommit(fraction)
                        dragValue = nil
                    }
            )
        }
        .frame(height: 12)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
    }
}
