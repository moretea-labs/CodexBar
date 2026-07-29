import Foundation
import Carbon

struct Workspace: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case compose
    case actions
    case tasks
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compose: return "新任务"
        case .actions: return "项目操作"
        case .tasks: return "任务中心"
        case .history: return "历史记录"
        }
    }

    var systemImage: String {
        switch self {
        case .compose: return "square.and.pencil"
        case .actions: return "bolt.square"
        case .tasks: return "rectangle.stack"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

enum ExecutionMode: String, Codable, CaseIterable, Identifiable {
    case background
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .background: return "后台执行"
        case .terminal: return "终端交互"
        }
    }

    var shortTitle: String {
        switch self {
        case .background: return "后台"
        case .terminal: return "终端"
        }
    }

    var systemImage: String {
        switch self {
        case .background: return "bolt.fill"
        case .terminal: return "terminal.fill"
        }
    }

    var explanation: String {
        switch self {
        case .background:
            return "使用 codex exec，可同时运行多个任务；结果保留在任务中心。"
        case .terminal:
            return "打开 Terminal 并启动 Codex TUI，适合连续对话与人工审批。"
        }
    }
}

enum HotKeyPreset: String, Codable, CaseIterable, Identifiable {
    case optionSpace
    case controlSpace
    case controlOptionSpace
    case commandShiftSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlSpace: return "⌃ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .commandShiftSpace: return "⌘⇧ Space"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_Space) }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .controlSpace: return UInt32(controlKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        }
    }
}

enum BackgroundTaskStatus: String, Equatable {
    case running
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .running: return "执行中"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已停止"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "circle.dotted"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    var isRunning: Bool { self == .running }
}

enum CodexOutputBlockKind: String, Equatable {
    case agentMessage
    case reasoning
    case command
    case fileChange
    case mcpTool
    case webSearch
    case todoList
    case lifecycle
    case error
    case diagnostic
    case unknown

    var systemImage: String {
        switch self {
        case .agentMessage: return "sparkles"
        case .reasoning: return "brain.head.profile"
        case .command: return "terminal"
        case .fileChange: return "doc.badge.gearshape"
        case .mcpTool: return "wrench.and.screwdriver"
        case .webSearch: return "globe"
        case .todoList: return "checklist"
        case .lifecycle: return "circle.dotted"
        case .error: return "exclamationmark.triangle.fill"
        case .diagnostic: return "text.bubble"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}

enum CodexOutputBlockStatus: String, Equatable {
    case inProgress
    case completed
    case failed

    var title: String {
        switch self {
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }

    var systemImage: String {
        switch self {
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

struct CodexFileChange: Equatable {
    let path: String
    let kind: String

    var title: String {
        switch kind {
        case "add": return "新增"
        case "delete": return "删除"
        case "update": return "修改"
        default: return kind
        }
    }

    var systemImage: String {
        switch kind {
        case "add": return "plus.circle"
        case "delete": return "minus.circle"
        default: return "pencil.circle"
        }
    }
}

struct CodexTodo: Equatable {
    let text: String
    let completed: Bool
}

struct CodexTokenUsage: Equatable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?

    var summary: String? {
        var parts: [String] = []
        if let inputTokens { parts.append("输入 \(inputTokens)") }
        if let cachedInputTokens, cachedInputTokens > 0 { parts.append("缓存 \(cachedInputTokens)") }
        if let outputTokens { parts.append("输出 \(outputTokens)") }
        if let reasoningOutputTokens, reasoningOutputTokens > 0 { parts.append("推理 \(reasoningOutputTokens)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct CodexOutputBlock: Identifiable, Equatable {
    let id: String
    var kind: CodexOutputBlockKind
    var title: String
    var body: String
    var detail: String
    var status: CodexOutputBlockStatus?
    var exitCode: Int?
    var fileChanges: [CodexFileChange]
    var todos: [CodexTodo]
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        kind: CodexOutputBlockKind,
        title: String,
        body: String = "",
        detail: String = "",
        status: CodexOutputBlockStatus? = nil,
        exitCode: Int? = nil,
        fileChanges: [CodexFileChange] = [],
        todos: [CodexTodo] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.detail = detail
        self.status = status
        self.exitCode = exitCode
        self.fileChanges = fileChanges
        self.todos = todos
        self.createdAt = createdAt
    }
}

enum CodexStreamMutation {
    case threadStarted(String)
    case turnStarted
    case upsert(CodexOutputBlock)
    case append(CodexOutputBlock)
    case turnCompleted(CodexTokenUsage?)
    case turnFailed(String)
    case ignored
}

enum CodexJSONEventParser {
    static func parse(line: String) -> CodexStreamMutation {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let event = object as? [String: Any],
              let type = event["type"] as? String else {
            return .append(
                CodexOutputBlock(
                    kind: .diagnostic,
                    title: "Codex 输出",
                    body: trimmed
                )
            )
        }

        switch type {
        case "thread.started":
            return .threadStarted(event["thread_id"] as? String ?? "")
        case "turn.started":
            return .turnStarted
        case "turn.completed":
            return .turnCompleted(parseUsage(event["usage"] as? [String: Any]))
        case "turn.failed":
            return .turnFailed(errorMessage(from: event) ?? "Codex 执行失败。")
        case "error":
            return .append(
                CodexOutputBlock(
                    kind: .error,
                    title: "运行错误",
                    body: errorMessage(from: event) ?? prettyJSON(event),
                    status: .failed
                )
            )
        case "item.started", "item.updated", "item.completed":
            guard let item = event["item"] as? [String: Any] else { return .ignored }
            return .upsert(parseItem(item, eventType: type))
        default:
            // Codex adds event types over time. Preserve unfamiliar records instead
            // of silently dropping information that may help diagnose a task.
            return .append(
                CodexOutputBlock(
                    kind: .unknown,
                    title: type,
                    body: prettyJSON(event)
                )
            )
        }
    }

    private static func parseItem(_ item: [String: Any], eventType: String) -> CodexOutputBlock {
        let id = item["id"] as? String ?? UUID().uuidString
        let type = item["type"] as? String ?? "unknown"
        let status = parseStatus(item["status"] as? String, eventType: eventType)

        switch type {
        case "agent_message", "assistant_message":
            return CodexOutputBlock(
                id: id,
                kind: .agentMessage,
                title: "Codex",
                body: item["text"] as? String ?? "",
                status: status
            )
        case "reasoning":
            return CodexOutputBlock(
                id: id,
                kind: .reasoning,
                title: "思考过程",
                body: item["text"] as? String ?? "",
                status: status
            )
        case "command_execution":
            return CodexOutputBlock(
                id: id,
                kind: .command,
                title: "执行命令",
                body: item["command"] as? String ?? "",
                detail: item["aggregated_output"] as? String ?? item["output"] as? String ?? "",
                status: status,
                exitCode: item["exit_code"] as? Int
            )
        case "file_change":
            let changes = (item["changes"] as? [[String: Any]] ?? []).map {
                CodexFileChange(
                    path: $0["path"] as? String ?? "未知文件",
                    kind: $0["kind"] as? String ?? "update"
                )
            }
            return CodexOutputBlock(
                id: id,
                kind: .fileChange,
                title: "文件变更",
                status: status,
                fileChanges: changes
            )
        case "mcp_tool_call":
            let server = item["server"] as? String ?? "MCP"
            let tool = item["tool"] as? String ?? "工具"
            let arguments = item["arguments"].map(prettyJSON) ?? ""
            let result = mcpResultText(item["result"])
            let error = ((item["error"] as? [String: Any])?["message"] as? String) ?? ""
            return CodexOutputBlock(
                id: id,
                kind: .mcpTool,
                title: "\(server) · \(tool)",
                body: arguments,
                detail: error.isEmpty ? result : error,
                status: error.isEmpty ? status : .failed
            )
        case "web_search":
            return CodexOutputBlock(
                id: id,
                kind: .webSearch,
                title: "搜索网络",
                body: item["query"] as? String ?? "",
                status: status
            )
        case "todo_list", "plan_update":
            let todos = (item["items"] as? [[String: Any]] ?? item["plan"] as? [[String: Any]] ?? []).map {
                CodexTodo(
                    text: $0["text"] as? String ?? $0["step"] as? String ?? "",
                    completed: ($0["completed"] as? Bool) == true || ($0["status"] as? String) == "completed"
                )
            }
            return CodexOutputBlock(
                id: id,
                kind: .todoList,
                title: "执行计划",
                status: status,
                todos: todos
            )
        case "error":
            return CodexOutputBlock(
                id: id,
                kind: .error,
                title: "执行错误",
                body: item["message"] as? String ?? prettyJSON(item),
                status: .failed
            )
        default:
            return CodexOutputBlock(
                id: id,
                kind: .unknown,
                title: type,
                body: prettyJSON(item),
                status: status
            )
        }
    }

    private static func parseStatus(_ value: String?, eventType: String) -> CodexOutputBlockStatus? {
        switch value {
        case "in_progress", "running": return .inProgress
        case "completed", "success", "succeeded": return .completed
        case "failed", "error": return .failed
        default:
            if eventType == "item.started" { return .inProgress }
            if eventType == "item.completed" { return .completed }
            return nil
        }
    }

    private static func parseUsage(_ usage: [String: Any]?) -> CodexTokenUsage? {
        guard let usage else { return nil }
        return CodexTokenUsage(
            inputTokens: usage["input_tokens"] as? Int,
            cachedInputTokens: usage["cached_input_tokens"] as? Int,
            outputTokens: usage["output_tokens"] as? Int,
            reasoningOutputTokens: usage["reasoning_output_tokens"] as? Int
        )
    }

    private static func errorMessage(from event: [String: Any]) -> String? {
        if let message = event["message"] as? String { return message }
        if let error = event["error"] as? [String: Any] {
            return error["message"] as? String ?? prettyJSON(error)
        }
        if let error = event["error"] as? String { return error }
        return nil
    }

    private static func mcpResultText(_ value: Any?) -> String {
        guard let value else { return "" }
        if let result = value as? [String: Any],
           let content = result["content"] as? [[String: Any]] {
            let text = content.compactMap { block -> String? in
                if let text = block["text"] as? String { return text }
                return nil
            }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return prettyJSON(value)
    }

    private static func prettyJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

struct BackgroundTaskSession: Identifiable, Equatable {
    let id: UUID
    let historyID: UUID
    let prompt: String
    let workspaceName: String
    let workspacePath: String
    let createdAt: Date
    var finishedAt: Date?
    var threadID: String?
    var blocks: [CodexOutputBlock]
    var outputRevision: Int
    var usage: CodexTokenUsage?
    var status: BackgroundTaskStatus
    var exitCode: Int32?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        historyID: UUID,
        prompt: String,
        workspaceName: String,
        workspacePath: String,
        createdAt: Date = Date(),
        finishedAt: Date? = nil,
        threadID: String? = nil,
        blocks: [CodexOutputBlock] = [],
        outputRevision: Int = 0,
        usage: CodexTokenUsage? = nil,
        status: BackgroundTaskStatus = .running,
        exitCode: Int32? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.historyID = historyID
        self.prompt = prompt
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.threadID = threadID
        self.blocks = blocks
        self.outputRevision = outputRevision
        self.usage = usage
        self.status = status
        self.exitCode = exitCode
        self.errorMessage = errorMessage
    }

    var displayPrompt: String {
        prompt.isEmpty ? "未命名后台任务" : prompt
    }
}

struct TaskHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let prompt: String
    let workspaceName: String
    let workspacePath: String
    let mode: ExecutionMode
    let createdAt: Date
    var succeeded: Bool?

    init(
        id: UUID = UUID(),
        prompt: String,
        workspaceName: String,
        workspacePath: String,
        mode: ExecutionMode,
        createdAt: Date = Date(),
        succeeded: Bool? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.mode = mode
        self.createdAt = createdAt
        self.succeeded = succeeded
    }
}

struct PersistedPreferences: Codable {
    var workspaces: [Workspace]
    var selectedWorkspaceID: UUID?
    var executionMode: ExecutionMode
    var hotKeyPreset: HotKeyPreset
    var customCodexPath: String
    var history: [TaskHistoryItem]
}
