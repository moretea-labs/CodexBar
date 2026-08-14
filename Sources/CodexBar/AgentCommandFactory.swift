import Foundation

/// What the runner should execute. `stdinPrompt` is nil when the prompt has
/// already been embedded into the shell command (e.g. grok's `--single`).
struct AgentCommandPlan {
    let shellCommand: String
    let stdinPrompt: String?
}

/// Builds the shell commands that drive each agent, in both background and
/// terminal modes. All values are shell-quoted before joining.
enum AgentCommandFactory {
    /// Tools granted to non-interactive claude runs. Runs under
    /// `bypassPermissions`, so keeping the tool set tight limits blast radius.
    private static let claudeAllowedTools = "Read,Edit,Write,Bash,Glob,Grep,TodoWrite"
    private static let claudePlanTools = "Read,Glob,Grep"
    /// Tools granted to non-interactive grok runs.
    private static let grokAllowedTools = "Read,Edit,Write,Bash,Glob,Grep"
    private static let grokPlanTools = "Read,Glob,Grep"

    static func backgroundPlan(
        agent: AgentKind,
        executablePath: String,
        workspacePath: String,
        prompt: String,
        intent: AgentTaskIntent = .execute,
        resumeSessionID: String? = nil
    ) -> AgentCommandPlan {
        let exe = ShellUtilities.shellQuote(executablePath)
        let ws = ShellUtilities.shellQuote(workspacePath)
        let effectivePrompt = intent == .plan ? planningPrompt(for: prompt) : prompt
        let quotedPrompt = ShellUtilities.shellQuote(effectivePrompt)

        switch agent {
        case .chatgpt:
            preconditionFailure("ChatGPT is browser-routed and must not enter AgentCommandFactory")
        case .codex:
            // Approval policy is a root Codex option, so it must appear before
            // the `exec` subcommand. Putting it after `codex exec` is rejected
            // by current Codex CLI versions.
            var parts = [
                "exec", exe,
                "-a", "never",
                "exec",
                "--cd", ws,
                "--sandbox", intent == .plan ? "read-only" : "workspace-write",
                "--json"
            ]
            if let resumeSessionID = resumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !resumeSessionID.isEmpty {
                parts.append("resume")
                parts.append(ShellUtilities.shellQuote(resumeSessionID))
            }
            parts.append("-")
            return AgentCommandPlan(shellCommand: parts.joined(separator: " "), stdinPrompt: effectivePrompt)

        case .claude:
            // Claude has no --cd flag; the working directory comes from the
            // runner's currentDirectoryURL. The prompt is piped via stdin.
            let command = [
                "exec", exe,
                "-p",
                "--output-format", "stream-json",
                "--permission-mode", "bypassPermissions",
                "--no-session-persistence",
                "--allowedTools", ShellUtilities.shellQuote(intent == .plan ? claudePlanTools : claudeAllowedTools)
            ].joined(separator: " ")
            return AgentCommandPlan(shellCommand: command, stdinPrompt: effectivePrompt)

        case .grok:
            // grok --single takes the prompt as an argument, not stdin.
            let command = [
                "exec", exe,
                "--single", quotedPrompt,
                "--cwd", ws,
                "--output-format", "streaming-messages-json",
                "--permission-mode", "bypassPermissions",
                "--tools", ShellUtilities.shellQuote(intent == .plan ? grokPlanTools : grokAllowedTools)
            ].joined(separator: " ")
            return AgentCommandPlan(shellCommand: command, stdinPrompt: nil)
        }
    }

    private static func planningPrompt(for prompt: String) -> String {
        """
        你现在执行一次只读规划。禁止修改、创建、删除或重命名任何文件，禁止执行会改变工作区或外部状态的操作。先检查现有实现与约束，再输出可直接交给执行阶段使用的、决策完整的实施计划，并包含验证步骤。不要开始实施。

        用户请求：
        \(prompt)
        """
    }

    /// The interactive (TUI) command handed to the terminal template.
    static func terminalCommand(
        agent: AgentKind,
        executablePath: String,
        workspacePath: String,
        prompt: String
    ) -> String {
        let exe = ShellUtilities.shellQuote(executablePath)
        let ws = ShellUtilities.shellQuote(workspacePath)
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotedPrompt = trimmed.isEmpty ? "" : ShellUtilities.shellQuote(trimmed)

        switch agent {
        case .chatgpt:
            preconditionFailure("ChatGPT is browser-routed and must not enter AgentCommandFactory")
        case .codex:
            var parts = ["clear;", exe, "--cd", ws]
            if !quotedPrompt.isEmpty { parts.append(quotedPrompt) }
            return parts.joined(separator: " ")

        case .claude:
            var parts = ["clear;", "cd", ws, "&&", exe]
            if !quotedPrompt.isEmpty { parts.append(quotedPrompt) }
            return parts.joined(separator: " ")

        case .grok:
            var parts = ["clear;", exe]
            if !quotedPrompt.isEmpty { parts.append(quotedPrompt) }
            parts.append("--cwd")
            parts.append(ws)
            return parts.joined(separator: " ")
        }
    }
}
