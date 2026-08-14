import XCTest
@testable import CodexBar

final class ClaudeStreamParserTests: XCTestCase {
    private var parser: ClaudeStreamParser!

    override func setUp() {
        super.setUp()
        parser = ClaudeStreamParser()
    }

    func testSystemEventStartsThread() {
        guard case .threadStarted(let sid) = parser.parse(
            #"{"type":"system","subtype":"init","session_id":"abc123"}"#
        ) else { return XCTFail("expected .threadStarted") }
        XCTAssertEqual(sid, "abc123")
    }

    func testSystemEventWithoutSessionIsIgnored() {
        guard case .ignored = parser.parse(#"{"type":"system","subtype":"init"}"#)
        else { return XCTFail("expected .ignored") }
    }

    func testMessageStartStartsTurn() {
        let line = #"{"type":"stream_event","event":{"type":"message_start","message":{}}}"#
        guard case .turnStarted = parser.parse(line) else { return XCTFail("expected .turnStarted") }
    }

    func testTextBlockStartUpsertsAgentMessage() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#
        guard case .upsert(let block) = parser.parse(line) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.id, "claude-0")
        XCTAssertEqual(block.kind, .agentMessage)
        XCTAssertEqual(block.status, .inProgress)
    }

    func testTextDeltaAppendsToBlock() {
        _ = parser.parse(
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#
        )
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好"}}}"#
        guard case .appendText(let text, let id) = parser.parse(line) else { return XCTFail("expected .appendText") }
        XCTAssertEqual(text, "你好")
        XCTAssertEqual(id, "claude-0")
    }

    func testThinkingBlockUpsertsReasoning() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}"#
        guard case .upsert(let block) = parser.parse(line) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.kind, .reasoning)
        XCTAssertEqual(block.id, "claude-thinking-0")
    }

    func testToolUseBlockAndInputDelta() {
        let start = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01","name":"Bash","input":{}}}}"#
        guard case .upsert(let block) = parser.parse(start) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.id, "toolu_01")
        XCTAssertEqual(block.kind, .command)
        XCTAssertEqual(block.title, "Bash")

        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"cmd\":\"ls\"}"}}}"#
        guard case .appendText(let partial, let id) = parser.parse(delta) else { return XCTFail("expected .appendText") }
        XCTAssertEqual(partial, #"{"cmd":"ls"}"#)
        XCTAssertEqual(id, "toolu_01")
    }

    func testToolResultMarksCommandCompleted() {
        _ = parser.parse(
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01","name":"Bash","input":{}}}}"#
        )
        let line = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":"已执行"}]}}"#
        guard case .upsert(let block) = parser.parse(line) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.id, "toolu_01")
        XCTAssertEqual(block.title, "Bash")
        XCTAssertEqual(block.detail, "已执行")
        XCTAssertEqual(block.status, .completed)
    }

    func testAssistantTextBlockWithoutStreamEventsUpsertsAgentMessage() {
        let line = #"{"type":"assistant","message":{"id":"msg_1","content":[{"type":"text","text":"完成了"}]}}"#
        guard case .upsert(let block) = parser.parse(line) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.kind, .agentMessage)
        XCTAssertEqual(block.body, "完成了")
        XCTAssertEqual(block.id, "msg_1-0")
    }

    func testAssistantToolUseBlockWithoutStreamEventsUpsertsCommand() {
        let line = #"{"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_09","name":"Glob","input":{}}]}}"#
        guard case .upsert(let block) = parser.parse(line) else { return XCTFail("expected .upsert") }
        XCTAssertEqual(block.kind, .command)
        XCTAssertEqual(block.title, "Glob")
        XCTAssertEqual(block.id, "toolu_09")
    }

    func testResultCompletesTurnWithUsage() {
        _ = parser.parse(
            #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":10,"output_tokens":5}}}"#
        )
        let line = #"{"type":"result","subtype":"success","result":"","is_error":false}"#
        guard case .turnCompleted(let usage) = parser.parse(line) else { return XCTFail("expected .turnCompleted") }
        XCTAssertEqual(usage?.inputTokens, 10)
        XCTAssertEqual(usage?.outputTokens, 5)
    }

    func testErrorResultFailsTurn() {
        let line = #"{"type":"result","subtype":"error","result":"boom","is_error":true}"#
        guard case .turnFailed(let message) = parser.parse(line) else { return XCTFail("expected .turnFailed") }
        XCTAssertTrue(message.contains("boom"))
    }

    func testSummaryAppendsFallbackMessage() {
        let line = #"{"type":"summary","summary":"完成","result":"收尾内容"}"#
        guard case .append(let block) = parser.parse(line) else { return XCTFail("expected .append") }
        XCTAssertEqual(block.kind, .agentMessage)
        XCTAssertEqual(block.body, "收尾内容")
    }

    func testMalformedLineBecomesDiagnostic() {
        guard case .append(let block) = parser.parse("not-json") else { return XCTFail("expected .append") }
        XCTAssertEqual(block.kind, .diagnostic)
    }
}
