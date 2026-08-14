import Foundation

/// Turns one NDJSON line from an agent's stream into a UI mutation.
/// Parsers may hold per-run state (e.g. incremental text accumulation).
protocol AgentOutputParsing {
    func parse(_ line: String) -> CodexStreamMutation
}

enum AgentParserRegistry {
    static func parser(for agent: AgentKind) -> AgentOutputParsing {
        switch agent {
        case .chatgpt:
            preconditionFailure("ChatGPT is browser-routed and has no local output parser")
        case .codex: return CodexStreamParser()
        case .claude: return ClaudeStreamParser()
        case .grok: return GrokStreamParser()
        }
    }
}

/// Stateless wrapper over the existing codex JSONL parser.
struct CodexStreamParser: AgentOutputParsing {
    func parse(_ line: String) -> CodexStreamMutation {
        CodexJSONEventParser.parse(line: line)
    }
}
