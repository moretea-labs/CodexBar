import Foundation

/// Parses `claude -p --output-format stream-json` NDJSON into stream
/// mutations. Holds per-run state (index→block-id map, tool names, cached
/// usage) so incremental deltas land on the right block.
final class ClaudeStreamParser: AgentOutputParsing {
    private var indexToBlockID: [Int: String] = [:]
    private var toolUseIDToName: [String: String] = [:]
    private var cachedUsage: [String: Any]?
    private var turnCompletedEmitted = false

    func parse(_ line: String) -> CodexStreamMutation {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let event = object as? [String: Any] else {
            return .append(CodexOutputBlock(kind: .diagnostic, title: "Claude 输出", body: trimmed))
        }

        switch event["type"] as? String ?? "" {
        case "system":
            let sid = event["session_id"] as? String ?? ""
            return sid.isEmpty ? .ignored : .threadStarted(sid)

        case "assistant":
            return handleAssistant(event)

        case "user":
            return handleUser(event)

        case "stream_event":
            return handleStreamEvent(event)

        case "result":
            return handleResult(event)

        case "summary":
            return handleSummary(event)

        default:
            return .append(CodexOutputBlock(kind: .unknown, title: "Claude 事件", body: prettyJSON(event)))
        }
    }

    private func handleStreamEvent(_ event: [String: Any]) -> CodexStreamMutation {
        guard let sub = event["event"] as? [String: Any] else { return .ignored }
        let eventType = sub["type"] as? String ?? ""
        let index = sub["index"] as? Int ?? 0

        switch eventType {
        case "message_start":
            return .turnStarted

        case "content_block_start":
            guard let block = sub["content_block"] as? [String: Any] else { return .ignored }
            switch block["type"] as? String ?? "" {
            case "text":
                let id = "claude-\(index)"
                indexToBlockID[index] = id
                return .upsert(CodexOutputBlock(
                    id: id,
                    kind: .agentMessage,
                    title: "Claude",
                    status: .inProgress
                ))
            case "tool_use":
                let id = block["id"] as? String ?? "claude-tool-\(index)"
                indexToBlockID[index] = id
                toolUseIDToName[id] = block["name"] as? String ?? "工具"
                return .upsert(CodexOutputBlock(
                    id: id,
                    kind: .command,
                    title: block["name"] as? String ?? "工具",
                    status: .inProgress
                ))
            case "thinking":
                let id = "claude-thinking-\(index)"
                indexToBlockID[index] = id
                return .upsert(CodexOutputBlock(
                    id: id,
                    kind: .reasoning,
                    title: "思考过程",
                    status: .inProgress
                ))
            default:
                return .ignored
            }

        case "content_block_delta":
            guard let delta = sub["delta"] as? [String: Any] else { return .ignored }
            switch delta["type"] as? String ?? "" {
            case "text_delta":
                let text = delta["text"] as? String ?? ""
                return .appendText(text, to: indexToBlockID[index] ?? "claude-\(index)")
            case "input_json_delta":
                let partial = delta["partial_json"] as? String ?? ""
                return .appendText(partial, to: indexToBlockID[index] ?? "claude-tool-\(index)")
            case "thinking_delta":
                let text = delta["thinking"] as? String ?? ""
                return .appendText(text, to: indexToBlockID[index] ?? "claude-thinking-\(index)")
            default:
                return .ignored
            }

        case "content_block_stop":
            return .ignored

        case "message_delta":
            if let usage = sub["usage"] as? [String: Any] {
                cachedUsage = usage
            }
            return .ignored

        default:
            return .ignored
        }
    }

    private func handleAssistant(_ event: [String: Any]) -> CodexStreamMutation {
        guard let message = event["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return .ignored
        }
        // Fallback path: full assistant message arrives without stream events.
        let messageID = message["id"] as? String ?? "claude"
        var mutation: CodexStreamMutation = .ignored
        for (idx, item) in content.enumerated() {
            switch item["type"] as? String ?? "" {
            case "text":
                mutation = .upsert(CodexOutputBlock(
                    id: "\(messageID)-\(idx)",
                    kind: .agentMessage,
                    title: "Claude",
                    body: item["text"] as? String ?? "",
                    status: .completed
                ))
            case "tool_use":
                let id = item["id"] as? String ?? "\(messageID)-\(idx)"
                toolUseIDToName[id] = item["name"] as? String ?? "工具"
                mutation = .upsert(CodexOutputBlock(
                    id: id,
                    kind: .command,
                    title: item["name"] as? String ?? "工具",
                    body: prettyJSON(item["input"]),
                    status: .completed
                ))
            default:
                break
            }
        }
        return mutation
    }

    private func handleUser(_ event: [String: Any]) -> CodexStreamMutation {
        guard let message = event["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return .ignored
        }
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

    private func handleResult(_ event: [String: Any]) -> CodexStreamMutation {
        if let isError = event["is_error"] as? Bool, isError,
           let message = event["result"] as? String, !message.isEmpty {
            return .turnFailed(message)
        }
        turnCompletedEmitted = true
        return .turnCompleted(parseUsage(cachedUsage))
    }

    private func handleSummary(_ event: [String: Any]) -> CodexStreamMutation {
        guard !turnCompletedEmitted,
              let text = event["result"] as? String, !text.isEmpty else {
            return .ignored
        }
        return .append(CodexOutputBlock(
            kind: .agentMessage,
            title: "Claude",
            body: text,
            status: .completed
        ))
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
