import Foundation

/// A user-editable AppleScript template that opens a command in a chosen
/// terminal app. Placeholders `{command}` and `{cwd}` are replaced at launch.
struct TerminalTemplate: Codable, Equatable {
    var source: String

    static let placeholders = ["{command}", "{cwd}"]

    static let defaultSource = TerminalTemplate.presetTerminal

    static let presets: [(name: String, source: String)] = [
        ("Terminal", presetTerminal),
        ("iTerm2", presetTerminaliTerm2)
    ]

    private static var presetTerminal: String {
        """
        tell application "Terminal"
            activate
            do script "{command}"
        end tell
        """
    }

    private static var presetTerminaliTerm2: String {
        """
        tell application "iTerm"
            create window with default profile
            tell current session of current window
                write text "{command}"
            end tell
        end tell
        """
    }

    init(source: String = TerminalTemplate.defaultSource) {
        self.source = source
    }

    func render(command: String, cwd: String) -> String {
        source
            .replacingOccurrences(of: "{command}", with: ShellUtilities.appleScriptQuote(command))
            .replacingOccurrences(of: "{cwd}", with: ShellUtilities.appleScriptQuote(cwd))
    }
}
