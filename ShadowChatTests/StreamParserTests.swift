import XCTest
@testable import ShadowChat

final class StreamParserTests: XCTestCase {
    func testClaudeDeltasAndSession() {
        var parser = ClaudeStreamParser()
        XCTAssertEqual(
            parser.consume(#"{"type":"system","subtype":"init","session_id":"sess-1"}"#),
            nil
        )
        XCTAssertEqual(parser.sessionID, "sess-1")
        let first = parser.consume(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}"#)
        XCTAssertEqual(first, "Hi")
        let second = parser.consume(#"{"type":"stream_event","event":{"delta":{"type":"text_delta","text":" there"}}}"#)
        XCTAssertEqual(second, "Hi there")
        XCTAssertNil(parser.consume(#"{"type":"result","result":"ignored because deltas arrived"}"#))
        XCTAssertEqual(parser.text, "Hi there")
    }

    func testClaudeResultFallback() {
        var parser = ClaudeStreamParser()
        XCTAssertEqual(parser.consume(#"{"type":"result","result":"Done","session_id":"abc"}"#), "Done")
        XCTAssertEqual(parser.sessionID, "abc")
    }

    func testCodexThreadAndMessage() {
        var parser = CodexStreamParser()
        XCTAssertNil(parser.consume(#"{"type":"thread.started","thread_id":"thread-9"}"#))
        XCTAssertEqual(parser.threadID, "thread-9")
        XCTAssertEqual(
            parser.consume(#"{"type":"agent_message_content_delta","delta":"One"}"#),
            "One"
        )
        XCTAssertEqual(
            parser.consume(#"{"type":"item.completed","item":{"type":"agent_message","text":"One two"}}"#),
            "One two"
        )
    }

    func testCursorPartialAppends() {
        var parser = CursorStreamParser()
        XCTAssertNil(parser.consume(#"{"type":"system","subtype":"init","session_id":"chat-1"}"#))
        XCTAssertEqual(parser.sessionID, "chat-1")
        XCTAssertEqual(
            parser.consume(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hel"}]},"session_id":"chat-1"}"#),
            "Hel"
        )
        XCTAssertEqual(
            parser.consume(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"lo"}]}}"#),
            "Hello"
        )
        XCTAssertNil(parser.consume(#"{"type":"thinking","subtype":"delta","text":"secret"}"#))
        XCTAssertEqual(parser.text, "Hello")
    }

    func testGrokSSE() {
        var state = GrokParseState()
        XCTAssertNil(GrokSSE.consume("event: response.output_text.delta", state: &state))
        XCTAssertEqual(
            GrokSSE.consume(#"data: {"type":"response.output_text.delta","delta":"Yo"}"#, state: &state),
            "Yo"
        )
        XCTAssertNil(
            GrokSSE.consume(#"data: {"type":"response.completed","response":{"id":"resp_9"}}"#, state: &state)
        )
        XCTAssertEqual(state.responseID, "resp_9")
        XCTAssertEqual(state.text, "Yo")
    }

    func testSplitUTF8CodePointStaysOneLine() {
        var buffer = UTF8LineBuffer()
        let euro = Data("€".utf8)
        XCTAssertEqual(buffer.append(Data(euro.prefix(2))), [])
        let rest = euro.dropFirst(2) + Data(" line\nnext".utf8)
        XCTAssertEqual(buffer.append(Data(rest)), ["€ line"])
        XCTAssertEqual(buffer.finish(), "next")
    }

    func testTruncatedChunksDoNotInventText() {
        var claude = ClaudeStreamParser()
        var codex = CodexStreamParser()
        var cursor = CursorStreamParser()
        var grok = GrokParseState()
        let chunks = [
            "{",
            "{\"type\":\"stream_event\"",
            "{\"type\":\"agent_message_content_delta\",\"delta\":",
            "data: {\"type\":\"response.output_text.delta\",\"delta\":",
            "{\"type\":\"assistant\",\"message\":{\"content\":[",
            "not json",
            ""
        ]
        for _ in 0..<50 {
            for chunk in chunks {
                _ = claude.consume(chunk)
                _ = codex.consume(chunk)
                _ = cursor.consume(chunk)
                _ = GrokSSE.consume(chunk, state: &grok)
            }
        }
        XCTAssertEqual(claude.text, "")
        XCTAssertEqual(codex.text, "")
        XCTAssertEqual(cursor.text, "")
        XCTAssertEqual(grok.text, "")
        XCTAssertNil(claude.sessionID)
        XCTAssertEqual(claude.consume(#"{"type":"result","result":"kept","session_id":"s1"}"#), "kept")
        XCTAssertEqual(claude.sessionID, "s1")
    }
}
