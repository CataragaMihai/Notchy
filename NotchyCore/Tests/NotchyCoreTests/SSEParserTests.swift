import Testing
@testable import NotchyCore

struct SSEParserTests {
    @Test func recordedStreamWithThinking() {
        let fixture = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-sonnet-5-5","usage":{"input_tokens":4790,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: ping
        data: {"type": "ping"}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" world"}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":42}}

        event: message_stop
        data: {"type":"message_stop"}
        """
        let events = fixture.split(separator: "\n").compactMap { SSEParser.event(fromLine: String($0)) }
        #expect(events == [
            .messageStart(inputTokens: 4790),
            .thinkingStarted,
            .textDelta("Hello"),
            .textDelta(" world"),
            .messageDelta(stopReason: "end_turn", outputTokens: 42),
            .messageStop,
        ])
    }

    @Test func errorEvent() {
        let line = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(SSEParser.event(fromLine: line) == .error(type: "overloaded_error", message: "Overloaded"))
    }

    @Test func lineCutOffMidEventIsIgnored() {
        #expect(SSEParser.event(fromLine: #"data: {"type":"content_block_delta","index":1,"del"#) == nil)
    }

    @Test func nonDataLinesAreIgnored() {
        #expect(SSEParser.event(fromLine: "event: content_block_delta") == nil)
        #expect(SSEParser.event(fromLine: "") == nil)
        #expect(SSEParser.event(fromLine: ": comment") == nil)
    }

    @Test func unknownEventTypesAreIgnored() {
        #expect(SSEParser.event(fromLine: #"data: {"type":"something_new","x":1}"#) == nil)
    }
}
