import AppKit
import Foundation

enum TerminalLauncher {
    static func launch(
        executablePath: String,
        workspacePath: String,
        initialPrompt: String
    ) throws {
        var commandParts = [
            "clear;",
            ShellUtilities.shellQuote(executablePath),
            "--cd",
            ShellUtilities.shellQuote(workspacePath)
        ]

        let prompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            commandParts.append(ShellUtilities.shellQuote(prompt))
        }

        let command = commandParts.joined(separator: " ")
        let scriptSource = """
        tell application "Terminal"
            activate
            do script "\(ShellUtilities.appleScriptQuote(command))"
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else {
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
