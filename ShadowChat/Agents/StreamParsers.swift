import Foundation

enum JSONLine {
    static func object(_ line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

struct ClaudeStreamParser {
    var sessionID: String?
    var text = ""
    private var sawDelta = false

    mutating func consume(_ line: String) -> String? {
        guard let obj = JSONLine.object(line) else { return nil }
        if let sid = obj["session_id"] as? String, !sid.isEmpty {
            sessionID = sid
        }
        let type = obj["type"] as? String ?? ""
        if type == "stream_event",
           let event = obj["event"] as? [String: Any],
           let delta = event["delta"] as? [String: Any],
           let chunk = delta["text"] as? String {
            sawDelta = true
            text += chunk
            return text
        }
        if type == "result", !sawDelta, let result = obj["result"] as? String {
            text = result
            return text
        }
        return nil
    }
}

struct CodexStreamParser {
    var threadID: String?
    var text = ""
    private var usedDelta = false

    mutating func consume(_ line: String) -> String? {
        guard let obj = JSONLine.object(line) else { return nil }
        if let id = obj["thread_id"] as? String, !id.isEmpty {
            threadID = id
        }
        let type = obj["type"] as? String ?? ""
        if type == "agent_message_content_delta" {
            if let delta = obj["delta"] as? String {
                usedDelta = true
                text += delta
                return text
            }
        }
        if let item = obj["item"] as? [String: Any], (item["type"] as? String) == "agent_message" {
            if let itemText = item["text"] as? String {
                if !usedDelta || itemText.count >= text.count {
                    text = itemText
                    return text
                }
            }
        }
        return nil
    }
}

struct CursorStreamParser {
    var sessionID: String?
    var text = ""

    mutating func consume(_ line: String) -> String? {
        guard let obj = JSONLine.object(line) else { return nil }
        if let sid = obj["session_id"] as? String, !sid.isEmpty {
            sessionID = sid
        }
        guard (obj["type"] as? String) == "assistant" else { return nil }
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return nil }
        var changed = false
        for block in content {
            guard (block["type"] as? String) == "text", let chunk = block["text"] as? String, !chunk.isEmpty else { continue }
            if text.isEmpty || chunk.hasPrefix(text) {
                text = chunk
            } else if text.hasPrefix(chunk) {
                continue
            } else {
                text += chunk
            }
            changed = true
        }
        return changed ? text : nil
    }
}

struct GrokParseState {
    var text = ""
    var responseID: String?
    var error: String?
}

enum GrokSSE {
    static func consume(_ line: String, state: inout GrokParseState) -> String? {
        var payload = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.hasPrefix("data:") {
            payload = String(payload.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        if payload.isEmpty || payload == "[DONE]" || payload.hasPrefix("event:") { return nil }
        guard let obj = JSONLine.object(payload) else { return nil }
        if let error = obj["error"] as? [String: Any], let message = error["message"] as? String {
            state.error = message
        }
        let type = obj["type"] as? String ?? ""
        if let response = obj["response"] as? [String: Any], let id = response["id"] as? String, !id.isEmpty {
            state.responseID = id
        }
        if type == "response.output_text.delta", let delta = obj["delta"] as? String {
            state.text += delta
            return state.text
        }
        return nil
    }
}
