import Foundation

/// Shared helpers for mapping Anthropic-style content blocks into the
/// CodexBar output model. Used by the claude and grok stream parsers.
enum AnthropicContentMapper {
    /// Extracts human-readable text from a `tool_result` payload, which may be
    /// a plain string, an array of content blocks, or arbitrary JSON.
    static func toolResultText(_ value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String { return text }
        if let blocks = value as? [[String: Any]] {
            let parts = blocks.compactMap { block -> String? in
                block["text"] as? String
            }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]) else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
