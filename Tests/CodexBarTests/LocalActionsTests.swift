import Foundation
import XCTest
@testable import CodexBar

final class LocalActionsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarLocalActionsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testDiscoverySeparatesPublishedActionsFromRawScripts() throws {
        try writeScript("scripts/build.sh")
        try writeScript("scripts/internal-helper.sh")
        try writeManifest(
            actions: [[
                "script": "scripts/build.sh",
                "title": "构建项目",
                "summary": "生成可运行产物",
                "whenToUse": ["修改代码后需要构建"],
                "risk": "low",
                "quickRun": true,
                "requiresConfirmation": false,
                "published": true
            ]]
        )

        let actions = LocalActionCatalog.discover(workspace: workspace)

        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions.filter(\.published).map(\.title), ["构建项目"])

        let helper = try XCTUnwrap(actions.first(where: { $0.relativePath == "scripts/internal-helper.sh" }))
        XCTAssertFalse(helper.published)
        XCTAssertEqual(helper.source, .discovered)
        XCTAssertTrue(helper.requiresConfirmation)
        XCTAssertFalse(helper.isQuickRunnable)
    }

    func testSearchMatchesWhenToUseInsteadOfRequiringScriptName() throws {
        try writeScript("scripts/restart-controller.sh")
        try writeManifest(
            actions: [[
                "script": "scripts/restart-controller.sh",
                "title": "重启 Controller",
                "summary": "恢复本地控制器",
                "whenToUse": ["MCP 连不上", "Controller 无响应"],
                "aliases": ["恢复 repo-harness"],
                "risk": "low",
                "quickRun": true,
                "requiresConfirmation": false,
                "published": true
            ]]
        )

        let actions = LocalActionCatalog.discover(workspace: workspace)
        let results = LocalActionCatalog.search(
            actions,
            query: "MCP 连不上",
            favoriteIDs: [],
            recentActionIDs: []
        )

        XCTAssertEqual(results.first?.title, "重启 Controller")
    }

    func testQuickRunRequiresPublishedLowRiskActionWithoutConfirmation() {
        let mediumRisk = makeAction(risk: .medium, quickRun: true, requiresConfirmation: false, published: true)
        let unpublished = makeAction(risk: .low, quickRun: true, requiresConfirmation: false, published: false)
        let needsConfirmation = makeAction(risk: .low, quickRun: true, requiresConfirmation: true, published: true)
        let safe = makeAction(risk: .low, quickRun: true, requiresConfirmation: false, published: true)

        XCTAssertFalse(mediumRisk.isQuickRunnable)
        XCTAssertFalse(unpublished.isQuickRunnable)
        XCTAssertFalse(needsConfirmation.isQuickRunnable)
        XCTAssertTrue(safe.isQuickRunnable)
    }

    private var workspace: Workspace {
        Workspace(name: "Fixture", path: temporaryDirectory.path)
    }

    private func writeScript(_ relativePath: String) throws {
        let url = temporaryDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/bash\necho ok\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func writeManifest(actions: [[String: Any]]) throws {
        let directory = temporaryDirectory.appendingPathComponent(".codexbar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: ["actions": actions],
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directory.appendingPathComponent("actions.json"))
    }

    private func makeAction(
        risk: LocalActionRisk,
        quickRun: Bool,
        requiresConfirmation: Bool,
        published: Bool
    ) -> LocalAction {
        LocalAction(
            id: UUID().uuidString,
            workspaceName: "Fixture",
            workspacePath: "/tmp/fixture",
            scriptPath: "/tmp/fixture/scripts/action.sh",
            relativePath: "scripts/action.sh",
            title: "Fixture Action",
            summary: "Fixture",
            whenToUse: [],
            aliases: [],
            risk: risk,
            quickRun: quickRun,
            requiresConfirmation: requiresConfirmation,
            published: published,
            source: .workspaceManifest,
            workingDirectory: "/tmp/fixture",
            arguments: [],
            modifiedAt: nil
        )
    }
}
