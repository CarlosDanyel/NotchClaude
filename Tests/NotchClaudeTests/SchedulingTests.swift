import XCTest
@testable import NotchClaude

final class SchedulingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        return formatter.date(from: text)!
    }

    func testDailyRepeatKeepsTimeOfDay() {
        let anchor = date("2026-10-20T09:30:00")
        let next = RepeatRule.daily.nextDate(after: date("2026-10-22T10:00:00"), anchor: anchor, calendar: calendar)
        XCTAssertEqual(next, date("2026-10-23T09:30:00"))
    }

    func testWeekdaysSkipWeekend() {
        let anchor = date("2026-10-23T08:00:00")
        let next = RepeatRule.weekdays.nextDate(after: date("2026-10-23T09:00:00"), anchor: anchor, calendar: calendar)
        XCTAssertEqual(next, date("2026-10-26T08:00:00"))
    }

    func testHourlyAdvancesPastNow() {
        let anchor = date("2026-10-22T08:15:00")
        let next = RepeatRule.hourly.nextDate(after: date("2026-10-22T11:20:00"), anchor: anchor, calendar: calendar)
        XCTAssertEqual(next, date("2026-10-22T12:15:00"))
    }

    func testNeverRepeatReturnsNil() {
        XCTAssertNil(RepeatRule.never.nextDate(after: Date(), anchor: Date()))
    }

    func testLimitTextParserReadsEpochFormat() {
        let hit = LimitTextParser.parse("Claude AI usage limit reached|1792666200")
        XCTAssertEqual(hit?.resetsAt, Date(timeIntervalSince1970: 1792666200))
    }

    func testLimitTextParserReadsClockFormat() {
        let now = date("2026-10-22T13:00:00")
        let hit = LimitTextParser.parse("5-hour limit reached ∙ resets 3pm", now: now, calendar: calendar)
        XCTAssertEqual(hit?.kind, "five_hour")
        XCTAssertEqual(hit?.resetsAt, date("2026-10-22T15:00:00"))
    }

    func testLimitTextParserDetectsWeekly() {
        let hit = LimitTextParser.parse("You've hit your weekly limit · resets Oct 24, 9am")
        XCTAssertEqual(hit?.kind, "seven_day")
        XCTAssertNotNil(hit?.resetsAt)
    }

    func testLimitTextParserIgnoresOtherErrors() {
        XCTAssertNil(LimitTextParser.parse("Error: file not found"))
    }

    func testArgumentSplitterHandlesQuotes() {
        XCTAssertEqual(ArgumentSplitter.split(#"--add-dir "~/My Designs" --model 'opus' -x a\ b"#), ["--add-dir", "~/My Designs", "--model", "opus", "-x", "a b"])
        XCTAssertEqual(ArgumentSplitter.split("   "), [])
    }

    func testTitleUsesFirstNonEmptyLine() {
        XCTAssertEqual(ClaudeTask.makeTitle(from: "\n\n  Criar landing page  \nmais detalhes"), "Criar landing page")
    }

    @MainActor
    func testCommandArgumentsForFreshAndResumedRuns() {
        let settings = AppSettings.shared
        var task = ClaudeTask(title: "T", prompt: "Faça algo", directory: "/tmp", scheduledAt: Date(), anchorDate: Date())
        let fresh = RunPlan(task: task, settings: settings)
        let freshArguments = ClaudeCommandBuilder.arguments(plan: fresh, settings: settings)
        XCTAssertFalse(fresh.isResume)
        XCTAssertTrue(freshArguments.contains("--session-id"))
        XCTAssertTrue(freshArguments.contains("stream-json"))

        task.resumeSessionId = "abc"
        task.nextPrompt = "continue"
        let resumed = RunPlan(task: task, settings: settings)
        let resumedArguments = ClaudeCommandBuilder.arguments(plan: resumed, settings: settings)
        XCTAssertTrue(resumed.isResume)
        XCTAssertEqual(resumed.prompt, "continue")
        XCTAssertEqual(resumedArguments[resumedArguments.firstIndex(of: "--resume")! + 1], "abc")
    }
}

final class PersistenceTests: XCTestCase {
    func testTaskDecodingToleratesMissingFields() throws {
        let data = Data(#"{"prompt":"Gerar relatório\nsegunda linha","directory":"/tmp","status":"queued","runs":[{"sessionId":"abc"}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode(ClaudeTask.self, from: data)
        XCTAssertEqual(task.title, "Gerar relatório")
        XCTAssertEqual(task.status, .queued)
        XCTAssertEqual(task.repeatRule, .never)
        XCTAssertEqual(task.runs.first?.sessionId, "abc")
        XCTAssertTrue(task.nextAttachments.isEmpty)
    }

    func testTaskRoundTrip() throws {
        let original = ClaudeTask(title: "T", prompt: "P", directory: "/tmp", scheduledAt: Date(timeIntervalSince1970: 1_800_000_000), anchorDate: Date(timeIntervalSince1970: 1_800_000_000), repeatRule: .weekly)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeTask.self, from: encoder.encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.repeatRule, .weekly)
        XCTAssertEqual(decoded.scheduledAt, original.scheduledAt)
    }
}
