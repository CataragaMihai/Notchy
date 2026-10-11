import Foundation

/// The parts of the Messages API stream that Notchy acts on.
public enum StreamEvent: Equatable, Sendable {
    case messageStart(inputTokens: Int?)
    case thinkingStarted
    case textDelta(String)
    case messageDelta(stopReason: String?, outputTokens: Int?)
    case messageStop
    case error(type: String, message: String)
}

/// Parses one line of the server-sent event stream.
///
/// Each event's payload is a single `data:` line of JSON whose `type` names the event,
/// so lines are parsed independently. This matters because `URLSession.AsyncBytes.lines`
/// drops the blank lines that would normally separate events.
public enum SSEParser {
    public static func event(fromLine line: String) -> StreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        switch type {
        case "message_start":
            let usage = (object["message"] as? [String: Any])?["usage"] as? [String: Any]
            return .messageStart(inputTokens: usage?["input_tokens"] as? Int)

        case "content_block_start":
            let block = object["content_block"] as? [String: Any]
            return block?["type"] as? String == "thinking" ? .thinkingStarted : nil

        case "content_block_delta":
            guard let delta = object["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return nil }
            return .textDelta(text)

        case "message_delta":
            let delta = object["delta"] as? [String: Any]
            let usage = object["usage"] as? [String: Any]
            return .messageDelta(stopReason: delta?["stop_reason"] as? String,
                                 outputTokens: usage?["output_tokens"] as? Int)

        case "message_stop":
            return .messageStop

        case "error":
            let error = object["error"] as? [String: Any]
            return .error(type: error?["type"] as? String ?? "unknown",
                          message: error?["message"] as? String ?? "")

        default:
            // ping, content_block_stop, signature and thinking deltas, and anything new.
            return nil
        }
    }
}
