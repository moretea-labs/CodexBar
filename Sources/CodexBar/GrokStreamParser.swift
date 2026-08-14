import Foundation

/// Parses `grok --single --output-format streaming-messages-json` NDJSON,
/// which follows the Anthropic Messages API wire format.
final class GrokStreamParser: AgentOutputParsing {
    private var indexToBlockID: [Int: String] = [:]
    private var toolUseIDToName: [String: String] = [:]
    private var cachedUsage: [String: Any]?
    private var completed = false

    func parse(_ line: String) -> CodexStreamMutation {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let event = object as? [String: Any] else {
            return .append(CodexOutputBlock(kind: .diagnostic, title: "Grok 输出", body: trimmed))
        }

        switch event["type"] as? String ?? "" {
        case "message_start":
            return .turnStarted

        case "content_block_start":
            return handleBlockStart(event)

        case "content_block_delta":
            return handleBlockDelta(event)

        case "content_block_stop":
            return .ignored

        case "message_delta":
            if let usage = event["usage"] as? [String: Any] {
                cachedUsage = usage
            }
            return .ignored

        case "message_stop":
            guard !completed else { return .ignored }
            completed = true
            return .turnCompleted(parseUsage(cachedUsage))

        case "user":
            return handleUser(event)

        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String
                ?? prettyJSON(event["error"])
            return .turnFailed(message)

        case "ping":
            return .ignored

        default:
            return .append(CodexOutputBlock(kind: .unknown, title: "Grok 事件", body: prettyJSON(event)))
        }
    }

    private func handleBlockStart(_ event: [String: Any]) -> CodexStreamMutation {
        let index = event["index"] as? Int ?? 0
        guard let block = event["content_block"] as? [String: Any] else { return .ignored }
        switch block["type"] as? String ?? "" {
        case "text":
            let id = "grok-\(index)"
            indexToBlockID[index] = id
            return .upsert(CodexOutputBlock(
                id: id,
                kind: .agentMessage,
                title: "Grok",
                status: .inProgress
            ))
        case "tool_use":
            let id = block["id"] as? String ?? "grok-tool-\(index)"
            indexToBlockID[index] = id
            toolUseIDToName[id] = block["name"] as? String ?? "工具"
            return .upsert(CodexOutputBlock(
                id: id,
                kind: .command,
                title: block["name"] as? String ?? "工具",
                status: .inProgress
            ))
        default:
            return .ignored
        }
    }

    private func handleBlockDelta(_ event: [String: Any]) -> CodexStreamMutation {
        let index = event["index"] as? Int ?? 0
        guard let delta = event["delta"] as? [String: Any] else { return .ignored }
        switch delta["type"] as? String ?? "" {
        case "text_delta":
            let text = delta["text"] as? String ?? ""
            return .appendText(text, to: indexToBlockID[index] ?? "grok-\(index)")
        case "input_json_delta":
            let partial = delta["partial_json"] as? String ?? ""
            return .appendText(partial, to: indexToBlockID[index] ?? "grok-tool-\(index)")
        default:
            return .ignored
        }
    }

    private func handleUser(_ event: [String: Any]) -> CodexStreamMutation {
        guard let content = event["content"] as? [[String: Any]] else { return .ignored }
        var mutation: CodexStreamMutation = .ignored
        for item in content where (item["type"] as? String) == "tool_result" {
            let toolUseID = item["tool_use_id"] as? String ?? ""
            let text = AnthropicContentMapper.toolResultText(item["content"])
            mutation = .upsert(CodexOutputBlock(
                id: toolUseID,
                kind: .command,
                title: toolUseIDToName[toolUseID] ?? "工具",
                body: text,
                detail: text,
                status: .completed
            ))
        }
        return mutation
    }

    private func parseUsage(_ usage: [String: Any]?) -> CodexTokenUsage? {
        guard let usage else { return nil }
        return CodexTokenUsage(
            inputTokens: usage["input_tokens"] as? Int,
            cachedInputTokens: usage["cache_read_input_tokens"] as? Int,
            outputTokens: usage["output_tokens"] as? Int,
            reasoningOutputTokens: usage["reasoning_tokens"] as? Int
        )
    }

    private func prettyJSON(_ value: Any?) -> String {
        guard let value else { return "" }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
