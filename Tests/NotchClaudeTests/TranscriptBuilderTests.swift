import XCTest
@testable import NotchClaude

final class TranscriptBuilderTests: XCTestCase {
    private func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    func testSuccessfulRunProducesSuccessOutcome() {
        var builder = TranscriptBuilder()
        builder.consume(json(#"{"type":"system","subtype":"init","session_id":"abc","model":"claude-fable-5-1","cwd":"/tmp/project","skills":[1,2]}"#))
        builder.consume(json(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm test"}}]},"parent_tool_use_id":null,"session_id":"abc"}"#))
        builder.consume(json(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]},"parent_tool_use_id":null}"#))
        builder.consume(json(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Pronto."}]},"parent_tool_use_id":null}"#))
        builder.consume(json(#"{"type":"result","subtype":"success","is_error":false,"result":"Pronto.","total_cost_usd":0.12,"num_turns":2,"usage":{"input_tokens":10,"cache_read_input_tokens":90,"output_tokens":5},"session_id":"abc"}"#))

        let (outcome, hit) = builder.outcome(cancelled: false, stderr: "")
        XCTAssertEqual(outcome, .success)
        XCTAssertNil(hit)
        XCTAssertTrue(builder.madeProgress)
        XCTAssertEqual(builder.sessionId, "abc")
        XCTAssertEqual(builder.result?.inputTokens, 100)

        guard case .tool(let call) = builder.items[1].kind else { return XCTFail("tool esperado") }
        XCTAssertEqual(call.summary, "npm test")
        XCTAssertTrue(call.isDone)
        XCTAssertEqual(call.output, "ok")
    }

    func testUsageLimitMessageIsDetectedWithResetTime() {
        var builder = TranscriptBuilder()
        builder.consume(json(#"{"type":"assistant","message":{"content":[{"type":"text","text":"You've hit your limit · resets 3pm"}]},"parent_tool_use_id":null,"error":"rate_limit","is_api_error_message":true,"api_error":"usage_limit_reached","api_error_params":{"rate_limit_info":{"status":"rejected","resetsAt":1792666200,"rateLimitType":"five_hour"}}}"#))
        builder.consume(json(#"{"type":"result","subtype":"success","is_error":true,"result":"You've hit your limit · resets 3pm","session_id":"abc"}"#))

        let (outcome, hit) = builder.outcome(cancelled: false, stderr: "")
        XCTAssertEqual(outcome, .rateLimited)
        XCTAssertEqual(hit?.kind, "five_hour")
        XCTAssertEqual(hit?.resetsAt, Date(timeIntervalSince1970: 1792666200))
        XCTAssertFalse(builder.madeProgress)
    }

    func testRejectedEventOnlyCountsWhenRunFails() {
        var builder = TranscriptBuilder()
        builder.consume(json(#"{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":1793156400,"rateLimitType":"seven_day","isUsingOverage":true}}"#))
        builder.consume(json(#"{"type":"result","subtype":"success","is_error":false,"result":"ok"}"#))
        XCTAssertEqual(builder.outcome(cancelled: false, stderr: "").0, .success)

        var failing = TranscriptBuilder()
        failing.consume(json(#"{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":1793156400,"rateLimitType":"seven_day"}}"#))
        failing.consume(json(#"{"type":"result","subtype":"success","is_error":true,"result":"Weekly limit reached"}"#))
        let (outcome, hit) = failing.outcome(cancelled: false, stderr: "")
        XCTAssertEqual(outcome, .rateLimited)
        XCTAssertEqual(hit?.kind, "seven_day")
    }

    func testModelCreditsErrorIsTaskFailureNotGlobalLimit() {
        var builder = TranscriptBuilder()
        builder.consume(json(#"{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":1793491200,"overageDisabledReason":"out_of_credits","isUsingOverage":false,"errorCode":"credits_required"}}"#))
        builder.consume(json(#"{"type":"assistant","message":{"content":[{"type":"text","text":"You're out of usage credits. Switch to another model."}]},"parent_tool_use_id":null,"error":"rate_limit","is_api_error_message":true,"api_error_status":429,"api_error":"model_requires_usage_credits","api_error_code":"credits_required"}"#))
        builder.consume(json(#"{"type":"result","subtype":"success","is_error":true,"result":"You're out of usage credits. Switch to another model.","api_error":"model_requires_usage_credits"}"#))

        let (outcome, hit) = builder.outcome(cancelled: false, stderr: "")
        XCTAssertEqual(outcome, .failed)
        XCTAssertNil(hit)
        XCTAssertEqual(builder.failureSummary, TranscriptBuilder.creditsMessage)
    }

    func testRateLimitEventUpdatesUsageWindows() {
        var builder = TranscriptBuilder()
        let usage = builder.consume(json(#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1792666200,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.14,"resetsAt":1792666200},"seven_day":{"utilization":0.28,"resetsAt":1793156400}}}}"#))
        XCTAssertEqual(usage?.fiveHour?.utilization, 0.14)
        XCTAssertEqual(usage?.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1793156400))
    }

    func testCancelledRunWins() {
        var builder = TranscriptBuilder()
        builder.consume(json(#"{"type":"notchclaude_exit","status":130,"cancelled":true,"stderr":""}"#))
        XCTAssertEqual(builder.outcome(cancelled: true, stderr: "").0, .cancelled)
    }

    func testProcessFailureWithoutResultIsFailed() {
        var builder = TranscriptBuilder()
        builder.consume(json(#"{"type":"notchclaude_exit","status":1,"cancelled":false,"stderr":"Invalid API key"}"#))
        XCTAssertEqual(builder.outcome(cancelled: false, stderr: "Invalid API key").0, .failed)
        XCTAssertEqual(builder.failureSummary, "Invalid API key")
    }

    func testStreamDeltasBuildLiveText() {
        var builder = TranscriptBuilder()
        builder.consume(json(#"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"text"}},"parent_tool_use_id":null}"#))
        builder.consume(json(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Olá"}},"parent_tool_use_id":null}"#))
        builder.consume(json(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":" mundo"}},"parent_tool_use_id":null}"#))
        XCTAssertEqual(builder.liveText, "Olá mundo")
        builder.consume(json(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Olá mundo"}]},"parent_tool_use_id":null}"#))
        XCTAssertEqual(builder.liveText, "")
    }
}
