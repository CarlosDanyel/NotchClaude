import SwiftUI

struct ClaudeSpinner: View {
    var size: CGFloat = 14
    var color: Color = Theme.accent
    var animating = true

    private static let frames = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let index = animating ? Int(context.date.timeIntervalSinceReferenceDate / 0.12) % Self.frames.count : 4
            Text(Self.frames[index])
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size * 1.2, height: size * 1.2)
        }
    }
}

struct StatusBadge: View {
    var status: TaskStatus
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if status == .running {
                ClaudeSpinner(size: compact ? 9 : 10)
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
            }
            Text(status.label)
                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2.5 : 3.5)
        .background(status.color.opacity(0.14), in: Capsule())
    }
}

struct UsageBar: View {
    var label: String
    var window: UsageWindow?
    var blocked = false

    private var fraction: Double { min(1, max(0, window?.utilization ?? 0)) }

    private var tint: Color {
        if blocked || fraction >= 0.95 { return Theme.danger }
        if fraction >= 0.75 { return Theme.warning }
        return Theme.success
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint).frame(width: max(3, proxy.size.width * (blocked ? 1 : fraction)))
                }
            }
            .frame(width: 30, height: 4)
            Text(window.map { Formatters.percent($0.utilization) } ?? "–")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .help(window.map { "\(label): \(Formatters.percent($0.utilization)) usado · renova \(Formatters.resetDescription($0.resetsAt))" } ?? "Sem leitura ainda — aparece após a primeira execução")
    }
}

struct ElapsedText: View {
    var since: Date
    var font: Font = .system(size: 10, weight: .medium).monospacedDigit()
    var color: Color = Theme.secondaryText

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Formatters.duration(context.date.timeIntervalSince(since)))
                .font(font)
                .foregroundStyle(color)
        }
    }
}
