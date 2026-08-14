import XCTest
@testable import CodexBar

final class AgentCommandFactoryTests: XCTestCase {
    private let exe = "/opt/homebrew/bin/codex"
    private let ws = "/tmp/codexbar-ws"
    private let prompt = "修复登录 bug"

    // MARK: - Background plans

    func testCodexBackgroundPlan() {
        let plan = AgentCommandFactory.backgroundPlan(
            agent: .codex, executablePath: exe, workspacePath: ws, prompt: prompt
        )

        XCTAssertEqual(plan.stdinPrompt, prompt)
        XCTAssertTrue(plan.shellCommand.hasPrefix("exec '/opt/homebrew/bin/codex'"))
        XCTAssertTrue(plan.shellCommand.contains(" -a never exec "))
        XCTAssertTrue(plan.shellCommand.contains("--cd '/tmp/codexbar-ws'"))
        XCTAssertTrue(plan.shellCommand.contains("--sandbox workspace-write"))
        XCTAssertTrue(plan.shellCommand.contains("--json"))
        XCTAssertTrue(plan.shellCommand.hasSuffix(" -"))
    }

    func testCodexResumeBackgroundPlanUsesExecResume() {
        let plan = AgentCommandFactory.backgroundPlan(
            agent: .codex,
            executablePath: exe,
            workspacePath: ws,
            prompt: "继续修复",
            resumeSessionID: "019abcde-1234-7000-8000-000000000001"
        )

        XCTAssertEqual(plan.stdinPrompt, "继续修复")
        XCTAssertTrue(plan.shellCommand.contains(" -a never exec "))
        XCTAssertTrue(plan.shellCommand.contains("--json resume '019abcde-1234-7000-8000-000000000001' -"))
    }

    func testCodexReadOnlyPlanUsesReadOnlySandboxAndPlanningPrompt() {
        let plan = AgentCommandFactory.backgroundPlan(
            agent: .codex,
            executablePath: exe,
            workspacePath: ws,
            prompt: "评估历史功能",
            intent: .plan
        )

        XCTAssertTrue(plan.shellCommand.contains("--sandbox read-only"))
        XCTAssertFalse(plan.shellCommand.contains("--sandbox workspace-write"))
        XCTAssertTrue(plan.stdinPrompt?.contains("只读规划") == true)
        XCTAssertTrue(plan.stdinPrompt?.contains("评估历史功能") == true)
    }

    func testClaudePlanRemovesMutationTools() {
        let plan = AgentCommandFactory.backgroundPlan(
            agent: .claude,
            executablePath: exe,
            workspacePath: ws,
            prompt: "plan it",
            intent: .plan
        )

        XCTAssertTrue(plan.shellCommand.contains("'Read,Glob,Grep'"))
        XCTAssertFalse(plan.shellCommand.contains("Edit,Write,Bash"))
        XCTAssertTrue(plan.stdinPrompt?.contains("只读规划") == true)
    }

    func testClaudeBackgroundPlanHasNoCdFlagAndStreamsViaStdin() {
        let claudeExe = "/Users/tester/.local/bin/claude"
        let plan = AgentCommandFactory.backgroundPlan(
            agent: .claude, executablePath: claudeExe, workspacePath: ws, prompt: prompt
        )

        XCTAssertEqual(plan.stdinPrompt, prompt)
        XCTAssertFalse(plan.shellCommand.contains("--cd"))
        XCTAssertTrue(plan.shellCommand.hasPrefix("exec '/Users/tester/.local/bin/claude'"))
        XCTAssertTrue(plan.shellCommand.contains("-p"))
        XCTAssertTrue(plan.shellCommand.contains("--output-format stream-json"))
        XCTAssertTrue(plan.shellCommand.contains("--permission-mode bypassPermissions"))
        XCTAssertTrue(plan.shellCommand.contains("--no-session-persistence"))
        XCTAssertTrue(plan.shellCommand.contains("--allowedTools 'Read,Edit,Write,Bash,Glob,Grep,TodoWrite'"))
    }

    func testGrokBackgroundPlanEmbedsPromptAsArgument() {
        let grokExe = "/Users/tester/.local/bin/grok"
        let plan = AgentCommandFactory.backgroundPlan(
            agent: .grok, executablePath: grokExe, workspacePath: ws, prompt: prompt
        )

        XCTAssertNil(plan.stdinPrompt)
        XCTAssertTrue(plan.shellCommand.hasPrefix("exec '/Users/tester/.local/bin/grok'"))
        XCTAssertTrue(plan.shellCommand.contains("--single '修复登录 bug'"))
        XCTAssertTrue(plan.shellCommand.contains("--cwd '/tmp/codexbar-ws'"))
        XCTAssertTrue(plan.shellCommand.contains("--output-format streaming-messages-json"))
        XCTAssertTrue(plan.shellCommand.contains("--permission-mode bypassPermissions"))
        XCTAssertTrue(plan.shellCommand.contains("--tools 'Read,Edit,Write,Bash,Glob,Grep'"))
    }

    func testGrokPromptWithQuotesIsShellQuoted() {
        let tricky = "它说 it's fine"
        let plan = AgentCommandFactory.backgroundPlan(
            agent: .grok, executablePath: exe, workspacePath: ws, prompt: tricky
        )
        XCTAssertNil(plan.stdinPrompt)
        XCTAssertTrue(plan.shellCommand.contains("--single '它说 it'\\''s fine'"))
    }

    // MARK: - Terminal commands

    func testCodexTerminalCommand() {
        let command = AgentCommandFactory.terminalCommand(
            agent: .codex, executablePath: exe, workspacePath: ws, prompt: prompt
        )
        XCTAssertTrue(command.hasPrefix("clear;"))
        XCTAssertTrue(command.contains("'/opt/homebrew/bin/codex' --cd '/tmp/codexbar-ws'"))
        XCTAssertTrue(command.contains("'修复登录 bug'"))
    }

    func testClaudeTerminalCommandCdsIntoWorkspace() {
        let claudeExe = "/Users/tester/.local/bin/claude"
        let command = AgentCommandFactory.terminalCommand(
            agent: .claude, executablePath: claudeExe, workspacePath: ws, prompt: prompt
        )
        XCTAssertTrue(command.hasPrefix("clear;"))
        XCTAssertTrue(command.contains("cd '/tmp/codexbar-ws' && '/Users/tester/.local/bin/claude'"))
        XCTAssertTrue(command.contains("'修复登录 bug'"))
    }

    func testGrokTerminalCommandPutsPromptBeforeCwd() {
        let grokExe = "/Users/tester/.local/bin/grok"
        let command = AgentCommandFactory.terminalCommand(
            agent: .grok, executablePath: grokExe, workspacePath: ws, prompt: prompt
        )
        XCTAssertTrue(command.hasPrefix("clear;"))
        XCTAssertTrue(command.contains("'/Users/tester/.local/bin/grok' '修复登录 bug' --cwd '/tmp/codexbar-ws'"))
    }

    func testTerminalCommandOmitsEmptyPrompt() {
        let command = AgentCommandFactory.terminalCommand(
            agent: .claude, executablePath: exe, workspacePath: ws, prompt: "   "
        )
        XCTAssertEqual(command, "clear; cd '/tmp/codexbar-ws' && '/opt/homebrew/bin/codex'")
    }
}
