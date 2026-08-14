import AppKit
import Foundation

enum TerminalLauncher {
    static func launch(
        agent: AgentKind,
        executablePath: String,
        workspacePath: String,
        initialPrompt: String,
        template: TerminalTemplate
    ) throws {
        let command = AgentCommandFactory.terminalCommand(
            agent: agent,
            executablePath: executablePath,
            workspacePath: workspacePath,
            prompt: initialPrompt
        )
        let source = template.render(command: command, cwd: workspacePath)
        try execute(source)
    }

    static func launchCommand(
        command: String,
        workspacePath: String,
        template: TerminalTemplate
    ) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CodexBarError.emptyCommand }

        let terminalCommand = [
            "clear;",
            "cd", ShellUtilities.shellQuote(workspacePath), "&&",
            trimmed
        ].joined(separator: " ")
        let source = template.render(command: terminalCommand, cwd: workspacePath)
        try execute(source)
    }

    private static func execute(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw CodexBarError.terminalLaunchFailed("无法创建 AppleScript。")
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? errorInfo.description
            throw CodexBarError.terminalLaunchFailed(message)
        }
    }
}
