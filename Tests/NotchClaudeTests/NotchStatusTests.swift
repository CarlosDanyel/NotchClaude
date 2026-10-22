import XCTest
@testable import NotchClaude

final class NotchStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ status: TaskStatus, finishedAt: Date? = nil) -> ClaudeTask {
        var task = ClaudeTask(title: "t", prompt: "p", directory: "/tmp", scheduledAt: now, anchorDate: now)
        task.status = status
        task.finishedAt = finishedAt
        return task
    }

    private func resolve(_ tasks: [ClaudeTask], limit: LimitState = LimitState(), running: Int = 0, acknowledgedAt: Date? = nil) -> NotchStatus {
        NotchStatus.resolve(tasks: tasks, limit: limit, running: running, acknowledgedAt: acknowledgedAt ?? now.addingTimeInterval(-60), now: now)
    }

    func testIdleWithoutPendingTasks() {
        XCTAssertEqual(resolve([task(.completed), task(.cancelled)]), .idle)
    }

    func testRunningWinsOverEverything() {
        let limit = LimitState(blockedUntil: now.addingTimeInterval(600))
        XCTAssertEqual(resolve([task(.queued), task(.failed, finishedAt: now)], limit: limit, running: 1), .running)
    }

    func testLimitBeforeQueueAndSchedule() {
        XCTAssertEqual(resolve([task(.queued), task(.rateLimited)]), .limited)
        let limit = LimitState(blockedUntil: now.addingTimeInterval(600))
        XCTAssertEqual(resolve([task(.scheduled)], limit: limit), .limited)
    }

    func testFailureOnlyUntilAcknowledged() {
        let failed = task(.failed, finishedAt: now.addingTimeInterval(-10))
        XCTAssertEqual(resolve([failed, task(.scheduled)]), .failed)
        XCTAssertEqual(resolve([failed, task(.scheduled)], acknowledgedAt: now), .scheduled)
    }

    func testQueuedBeforeScheduled() {
        XCTAssertEqual(resolve([task(.scheduled), task(.queued)]), .queued)
        XCTAssertEqual(resolve([task(.scheduled)]), .scheduled)
    }

    func testSpotifyNotificationParsing() {
        let state = SpotifyController.state(fromNotification: [
            "Player State": "Playing",
            "Track ID": "spotify:track:abc",
            "Name": "Música",
            "Artist": "Artista",
            "Album": "Álbum",
            "Duration": NSNumber(value: 215_000),
            "Playback Position": NSNumber(value: 12.5)
        ])
        XCTAssertEqual(state?.isPlaying, true)
        XCTAssertEqual(state?.track?.id, "spotify:track:abc")
        XCTAssertEqual(state?.track?.duration, 215)
        XCTAssertEqual(state?.position, 12.5)
        XCTAssertNil(state?.track?.artworkURL)
    }

    func testSpotifyStoppedNotificationClearsTrack() {
        let state = SpotifyController.state(fromNotification: ["Player State": "Stopped"])
        XCTAssertEqual(state, SpotifyState(isPlaying: false, track: nil, position: 0))
    }

    func testSpotifyScriptParsingHandlesLocaleDecimals() {
        let output = ["paused", "spotify:track:abc", "Música", "Artista", "Álbum", "215000", "42,75", "https://i.scdn.co/image/xyz"]
            .joined(separator: "\u{1E}") + "\n"
        let state = SpotifyController.state(fromScript: output)
        XCTAssertEqual(state?.isPlaying, false)
        XCTAssertEqual(state?.position, 42.75)
        XCTAssertEqual(state?.track?.duration, 215)
        XCTAssertEqual(state?.track?.artworkURL, URL(string: "https://i.scdn.co/image/xyz"))
    }

    func testSpotifyScriptParsingReadsVolume() {
        let output = ["playing", "spotify:track:abc", "M", "A", "B", "1000", "0", "", "37"].joined(separator: "\u{1E}")
        let state = SpotifyController.state(fromScript: output)
        XCTAssertEqual(state?.volume, 0.37)
        XCTAssertNil(state?.track?.artworkURL)
    }

    func testAccountUsageParsesPercentAndMicrosecondDates() {
        let json = """
        {"five_hour":{"utilization":22.0,"resets_at":"2026-10-22T12:49:59.609224+00:00"},
         "seven_day":{"utilization":3.0,"resets_at":"2026-10-29T01:59:59+00:00"},
         "seven_day_opus":null}
        """
        let snapshot = UsageMonitor.snapshot(from: Data(json.utf8), now: now)
        XCTAssertEqual(snapshot?.fiveHour?.utilization ?? 0, 0.22, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.sevenDay?.utilization ?? 0, 0.03, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.fiveHour?.resetsAt, UsageMonitor.date("2026-10-22T12:49:59+00:00"))
        XCTAssertNotNil(snapshot?.sevenDay?.resetsAt)
    }

    func testAccountUsageWithoutResetUsesWindowLength() {
        let json = #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":null}"#
        let snapshot = UsageMonitor.snapshot(from: Data(json.utf8), now: now)
        XCTAssertEqual(snapshot?.fiveHour?.resetsAt, now.addingTimeInterval(5 * 3600))
        XCTAssertNil(snapshot?.sevenDay)
        XCTAssertNil(UsageMonitor.snapshot(from: Data("{}".utf8)))
    }

    func testSpotifyScriptParsingNotRunningAndStopped() {
        XCTAssertNil(SpotifyController.state(fromScript: "\n"))
        XCTAssertEqual(SpotifyController.state(fromScript: "stopped\n")?.track, nil)
    }
}
