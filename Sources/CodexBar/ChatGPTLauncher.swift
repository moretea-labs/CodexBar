import AppKit
import ApplicationServices
import Foundation

enum ChatGPTLauncherError: LocalizedError {
    case chromeNotInstalled
    case invalidPromptURL
    case chromeAutomationFailed(String)

    var errorDescription: String? {
        switch self {
        case .chromeNotInstalled:
            return "未检测到 Google Chrome。"
        case .invalidPromptURL:
            return "无法生成 ChatGPT 新会话链接。"
        case .chromeAutomationFailed(let detail):
            return detail.isEmpty ? "无法控制 Google Chrome 打开 ChatGPT。" : "无法控制 Google Chrome：\(detail)"
        }
    }
}

enum ChatGPTLaunchOutcome: Equatable {
    case submitted
    case prefilledNeedsAccessibility
}

enum ChatGPTLauncher {
    static let chromeBundleIdentifier = "com.google.Chrome"
    static let defaultPromptPrefix = "@repo-harness6"

    static func combinedPrompt(prompt: String, prefix: String) -> String {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return prompt }
        guard !prompt.isEmpty else { return prefix }
        return prefix + "\n\n" + prompt
    }

    static func promptURL(prompt: String, prefix: String) throws -> URL {
        var components = URLComponents(string: "https://chatgpt.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: combinedPrompt(prompt: prompt, prefix: prefix))
        ]
        guard let url = components?.url else {
            throw ChatGPTLauncherError.invalidPromptURL
        }
        return url
    }

    /// Opens a new tab in the user's normal Google Chrome profile. ChatGPT's
    /// query deep-link sometimes submits automatically and sometimes only
    /// pre-fills the composer for logged-in users. When Accessibility access is
    /// already granted, CodexBar explicitly presses Return after the new tab has
    /// loaded if ChatGPT has not already created a conversation.
    @MainActor
    static func open(
        prompt: String,
        prefix: String,
        completion: @escaping (Result<ChatGPTLaunchOutcome, Error>) -> Void
    ) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeBundleIdentifier) != nil else {
            completion(.failure(ChatGPTLauncherError.chromeNotInstalled))
            return
        }

        let url: URL
        do {
            url = try promptURL(prompt: prompt, prefix: prefix)
        } catch {
            completion(.failure(error))
            return
        }

        let accessibilityTrusted = requestAccessibilityIfNeeded()
        DispatchQueue.global(qos: .userInitiated).async {
            var result = runChromeScript(url: url)
            if accessibilityTrusted,
               case .success(.prefilledNeedsAccessibility) = result {
                Thread.sleep(forTimeInterval: 0.25)
                pressReturnKey()
                result = .success(.submitted)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    private static func runChromeScript(
        url: URL
    ) -> Result<ChatGPTLaunchOutcome, Error> {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.standardOutput = stdout
        process.standardError = stderr
        process.arguments = [
            "-e",
            chromeAppleScript,
            url.absoluteString
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(error)
        }

        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let detail = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failure(ChatGPTLauncherError.chromeAutomationFailed(detail))
        }

        return .success(output == "submitted" ? .submitted : .prefilledNeedsAccessibility)
    }

    private static func pressReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static let chromeAppleScript = #"""
on run argv
    set targetURL to item 1 of argv

    tell application "Google Chrome"
        activate
        if (count of windows) is 0 then
            make new window
        end if
        tell front window
            set createdTab to make new tab at end of tabs with properties {URL:targetURL}
            set active tab index to (count of tabs)
        end tell

        repeat 80 times
            if loading of createdTab is false then exit repeat
            delay 0.1
        end repeat

        repeat 30 times
            set currentURL to URL of createdTab
            if currentURL contains "/c/" then return "submitted"
            if currentURL contains "q=" then exit repeat
            delay 0.1
        end repeat
    end tell

    return "prefilled"
end run
"""#
}
