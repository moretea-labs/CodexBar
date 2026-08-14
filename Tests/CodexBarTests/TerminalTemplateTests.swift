import XCTest
@testable import CodexBar

final class TerminalTemplateTests: XCTestCase {
    func testRenderReplacesPlaceholders() {
        let template = TerminalTemplate(source: "open terminal for {command} in {cwd}")
        XCTAssertEqual(template.render(command: "ls", cwd: "/tmp/ws"), "open terminal for ls in /tmp/ws")
    }

    func testRenderQuotesDoubleQuotes() {
        let template = TerminalTemplate(source: "do script \"{command}\"")
        XCTAssertEqual(template.render(command: "echo \"hi\"", cwd: "/tmp/ws"), "do script \"echo \\\"hi\\\"\"")
    }

    func testRenderEscapesBackslashAndNewline() {
        let template = TerminalTemplate(source: "show {command} in {cwd}")
        XCTAssertEqual(template.render(command: "a\nb\\c", cwd: "/tmp/ws"), "show a\\nb\\\\c in /tmp/ws")
    }

    func testDefaultSourceTargetsTerminal() {
        XCTAssertTrue(TerminalTemplate.defaultSource.contains("Terminal"))
        XCTAssertTrue(TerminalTemplate.defaultSource.contains("{command}"))
    }

    func testPresetsProvideTerminalAndIterm() {
        XCTAssertEqual(TerminalTemplate.presets.count, 2)
        XCTAssertEqual(TerminalTemplate.presets[0].name, "Terminal")
        XCTAssertTrue(TerminalTemplate.presets[0].source.contains("Terminal"))
        XCTAssertEqual(TerminalTemplate.presets[1].name, "iTerm2")
        XCTAssertTrue(TerminalTemplate.presets[1].source.contains("iTerm"))
    }

    func testRenderTwiceDoesNotDoubleEscape() {
        let template = TerminalTemplate(source: "run {command}")
        let once = template.render(command: "x", cwd: "y")
        XCTAssertEqual(once, "run x")
        // 第二次渲染同一份 source，不应引入额外转义
        XCTAssertEqual(once, template.render(command: "x", cwd: "y"))
    }
}
