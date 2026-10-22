import SwiftUI

enum Theme {
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let card = Color.white.opacity(0.06)
    static let cardHover = Color.white.opacity(0.1)
    static let stroke = Color.white.opacity(0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
    static let success = Color(red: 0.36, green: 0.82, blue: 0.55)
    static let warning = Color(red: 0.98, green: 0.76, blue: 0.33)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let info = Color(red: 0.45, green: 0.66, blue: 1.0)
    static let spotify = Color(red: 0.12, green: 0.84, blue: 0.38)

    static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let closeSpring = Animation.spring(response: 0.36, dampingFraction: 0.9)
}

extension TaskStatus {
    var color: Color {
        switch self {
        case .scheduled: return Theme.info
        case .queued: return Theme.warning
        case .running: return Theme.accent
        case .rateLimited: return Theme.danger
        case .completed: return Theme.success
        case .failed: return Theme.danger
        case .cancelled: return Theme.secondaryText
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: return "calendar.badge.clock"
        case .queued: return "hourglass"
        case .running: return "sparkle"
        case .rateLimited: return "gauge.with.needle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.octagon.fill"
        case .cancelled: return "stop.circle"
        }
    }
}

extension NotchStatus {
    var color: Color {
        switch self {
        case .running: return Theme.success
        case .queued: return Theme.warning
        case .limited, .failed: return Theme.danger
        case .scheduled: return Theme.info
        case .idle: return Theme.tertiaryText
        }
    }

    var label: String {
        switch self {
        case .running: return "Executando"
        case .queued: return "Na fila"
        case .limited: return "Tokens esgotados"
        case .failed: return "Uma tarefa falhou"
        case .scheduled: return "Tarefas agendadas"
        case .idle: return "Nada pendente"
        }
    }
}
