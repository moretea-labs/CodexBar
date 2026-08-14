import XCTest
@testable import CodexBar

final class ChatGPTLauncherTests: XCTestCase {
    func testCombinedPromptPrependsConfiguredPluginMention() {
        XCTAssertEqual(
            ChatGPTLauncher.combinedPrompt(
                prompt: "检查复制粘贴并修复",
                prefix: "@repo-harness6"
            ),
            "@repo-harness6\n\n检查复制粘贴并修复"
        )
    }

    func testEmptyPrefixDoesNotAddWhitespace() {
        XCTAssertEqual(
            ChatGPTLauncher.combinedPrompt(prompt: "hello", prefix: "   "),
            "hello"
        )
    }

    func testPromptURLTargetsFreshChatGPTRootAndEncodesPrompt() throws {
        let url = try ChatGPTLauncher.promptURL(
            prompt: "修复 copy & paste",
            prefix: "@repo-harness6"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "chatgpt.com")
        XCTAssertEqual(components.path, "/")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "q" })?.value,
            "@repo-harness6\n\n修复 copy & paste"
        )
    }
}
