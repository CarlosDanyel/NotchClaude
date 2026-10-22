import Foundation

enum Formatters {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEE, d MMM 'às' HH:mm"
        return formatter
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func clock(_ date: Date) -> String {
        time.string(from: date)
    }

    static func schedule(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "hoje \(clock(date))" }
        if calendar.isDateInTomorrow(date) { return "amanhã \(clock(date))" }
        if calendar.isDateInYesterday(date) { return "ontem \(clock(date))" }
        return dayTime.string(from: date)
    }

    static func resetDescription(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "às \(clock(date))" : schedule(date)
    }

    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        if abs(date.timeIntervalSince(now)) < 45 { return "agora" }
        return relative.localizedString(for: date, relativeTo: now)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h\(String(format: "%02d", (seconds % 3600) / 60))"
    }

    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    static func cost(_ value: Double) -> String {
        value > 0 && value < 0.01 ? "< US$ 0.01" : String(format: "US$ %.2f", value)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
