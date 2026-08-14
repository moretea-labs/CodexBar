import XCTest
@testable import CodexBar

final class GrokStreamParserTests: XCTestCase {
    private var parser: GrokStreamParser!

    override func setUp() {
        super.setUp()
        parser = GrokStreamParser()
    }

    func testMessageStartStartsTurn() {
        guard case .turnStarted = parser.parse(#"{"type":"message_start","message":{"id":"msg_1"}}"#)
        else { return XCTFail("expected .turnStarted") }
    }

    func testTextBlockStartAndDelta() {
        let start = #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#
        guard case .upsert(let block) = parser.parse(start) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.id, "grok-0")
        XCTAssertEqual(block.kind, .agentMessage)
        XCTAssertEqual(block.status, .inProgress)

        let delta = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好"}}"#
        guard case .appendText(let text, let id) = parser.parse(delta) else { return XCTFail("expected .appendText") }
        XCTAssertEqual(text, "你好")
        XCTAssertEqual(id, "grok-0")
    }

    func testToolUseBlockAndInputDelta() {
        let start = #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_x1","name":"Read","input":{}}}"#
        guard case .upsert(let block) = parser.parse(start) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.id, "toolu_x1")
        XCTAssertEqual(block.kind, .command)
        XCTAssertEqual(block.title, "Read")

        let delta = #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\":\"a\"}"}}"#
        guard case .appendText(let partial, let id) = parser.parse(delta) else { return XCTFail("expected .appendText") }
        XCTAssertEqual(partial, #"{"path":"a"}"#)
        XCTAssertEqual(id, "toolu_x1")
    }

    func testMessageStopCompletesTurnWithCachedUsage() {
        _ = parser.parse(
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":3,"output_tokens":7}}"#
        )
        guard case .turnCompleted(let usage) = parser.parse(#"{"type":"message_stop"}"#)
        else { return XCTFail("expected .turnCompleted") }
        XCTAssertEqual(usage?.inputTokens, 3)
        XCTAssertEqual(usage?.outputTokens, 7)
    }

    func testSecondMessageStopIsIgnored() {
        _ = parser.parse(#"{"type":"message_stop"}"#)
        guard case .ignored = parser.parse(#"{"type":"message_stop"}"#)
        else { return XCTFail("second message_stop should be ignored") }
    }

    func testToolResultMarksCommandCompleted() {
        _ = parser.parse(
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_x1","name":"Read","input":{}}}"#
        )
        let line = #"{"type":"user","content":[{"type":"tool_result","tool_use_id":"toolu_x1","content":"内容"}]}"#
        guard case .upsert(let block) = parser.parse(line) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.id, "toolu_x1")
        XCTAssertEqual(block.title, "Read")
        XCTAssertEqual(block.detail, "内容")
        XCTAssertEqual(block.status, .completed)
    }

    func testErrorEventFailsTurn() {
        let line = #"{"type":"error","error":{"message":"rate limited"}}"#
        guard case .turnFailed(let message) = parser.parse(line) else { return XCTFail("expected .turnFailed") }
        XCTAssertTrue(message.contains("rate limited"))
    }

    func testMalformedLineBecomesDiagnostic() {
        guard case .append(let block) = parser.parse("not-json") else { return XCTFail("expected .append") }
        XCTAssertEqual(block.kind, .diagnostic)
    }
}
