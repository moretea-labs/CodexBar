import Foundation
import Carbon

enum ShellUtilities {
    static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}

enum CodexBarError: LocalizedError {
    case codexNotFound
    case invalidWorkspace
    case emptyPrompt
    case processAlreadyRunning
    case processLaunchFailed(String)
    case terminalLaunchFailed(String)
    case hotKeyRegistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "没有找到 Codex CLI。请先在终端确认 `codex` 可用，或在设置中指定可执行文件路径。"
        case .invalidWorkspace:
            return "所选工作目录不存在，请重新添加。"
        case .emptyPrompt:
            return "后台执行需要先输入任务。"
        case .processAlreadyRunning:
            return "已有任务正在执行。"
        case .processLaunchFailed(let message):
            return "Codex 启动失败：\(message)"
        case .terminalLaunchFailed(let message):
            return "Terminal 启动失败：\(message)"
        case .hotKeyRegistrationFailed(let status):
            return "全局快捷键注册失败（\(status)），可能与系统或其他应用快捷键冲突。"
        }
    }
}
