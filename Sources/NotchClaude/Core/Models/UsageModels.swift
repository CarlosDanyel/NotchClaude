import Foundation

struct LimitState: Codable, Equatable {
    var blockedUntil: Date?
    var kind: String?
    var detectedAt: Date?

    func isBlocked(at now: Date = Date()) -> Bool {
        guard let blockedUntil else { return false }
        return now < blockedUntil
    }

    var kindLabel: String { LimitState.label(for: kind) }

    static func label(for kind: String?) -> String {
        switch kind {
        case "five_hour": return "Limite de 5h"
        case "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_overage_included": return "Limite semanal"
        case "overage": return "Limite de créditos"
        case "throttle": return "API ocupada"
        default: return "Limite de uso"
        }
    }
}

struct UsageWindow: Codable, Equatable {
    var utilization: Double
    var resetsAt: Date
}

struct UsageSnapshot: Codable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var updatedAt: Date
}

struct RateLimitHit: Equatable {
    var resetsAt: Date?
    var kind: String?
}
