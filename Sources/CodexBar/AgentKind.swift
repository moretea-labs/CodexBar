import Foundation

/// The agent CLIs CodexBar can drive. Each agent has its own path discovery,
/// argument construction and stream format, kept isolated behind this enum.
enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatgpt
    case codex
    case claude
    case grok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .grok: return "Grok"
        }
    }

    var usesLocalExecutable: Bool { self != .chatgpt }

    static var localAgents: [AgentKind] {
        allCases.filter(\.usesLocalExecutable)
    }

    /// Command name used with `command -v` for PATH discovery.
    var commandName: String { rawValue }

    var systemImage: String {
        switch self {
        case .chatgpt: return "bubble.left.and.bubble.right"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "sparkles"
        case .grok: return "sparkle"
        }
    }
}
