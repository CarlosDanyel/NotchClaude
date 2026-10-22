import Foundation

enum LimitTextParser {
    private static let epochPattern = try! NSRegularExpression(pattern: #"limit reached\|(\d{9,})"#, options: .caseInsensitive)
    private static let clockPattern = try! NSRegularExpression(pattern: #"resets?\s+(?:at\s+)?(?:[A-Za-z]{3,9}\.?\s+\d{1,2},?\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, options: .caseInsensitive)

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> RateLimitHit? {
        let lower = text.lowercased()
        let mentionsLimit = lower.contains("limit") && (lower.contains("usage") || lower.contains("hit your") || lower.contains("reached") || lower.contains("resets"))
        guard mentionsLimit else { return nil }

        let kind: String
        if lower.contains("weekly") || lower.contains("week") {
            kind = "seven_day"
        } else if lower.contains("5-hour") || lower.contains("five") || lower.contains("session") {
            kind = "five_hour"
        } else {
            kind = "five_hour"
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = epochPattern.firstMatch(in: text, range: range),
           let value = Range(match.range(at: 1), in: text).flatMap({ Double(text[$0]) }) {
            return RateLimitHit(resetsAt: Date(timeIntervalSince1970: value), kind: kind)
        }

        if let match = clockPattern.firstMatch(in: text, range: range),
           let hourRange = Range(match.range(at: 1), in: text),
           var hour = Int(text[hourRange]) {
            let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
            if let meridiemRange = Range(match.range(at: 3), in: text) {
                let meridiem = text[meridiemRange].lowercased()
                if meridiem == "pm", hour < 12 { hour += 12 }
                if meridiem == "am", hour == 12 { hour = 0 }
            }
            let parts = DateComponents(hour: hour, minute: minute)
            if let date = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) {
                return RateLimitHit(resetsAt: date, kind: kind)
            }
        }

        return RateLimitHit(resetsAt: nil, kind: kind)
    }
}
