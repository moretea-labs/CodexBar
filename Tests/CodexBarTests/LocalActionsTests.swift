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

    func testCustomizationPublishesDiscoveredActionAndUsesConfirmedMetadata() throws {
        try writeScript("scripts/repair.sh")
        let action = try XCTUnwrap(
            LocalActionCatalog.discover(workspace: workspace)
                .first(where: { $0.relativePath == "scripts/repair.sh" })
        )

        let customization = LocalActionCustomization(
            action: action,
            title: "修复本地环境",
            summary: "恢复项目依赖和缓存",
            whenToUse: ["构建工具无法启动"],
            aliases: ["修复环境"],
            risk: .low,
            quickRun: true
        )
        let curated = action.applying(customization)

        XCTAssertTrue(curated.published)
        XCTAssertTrue(curated.isCustomized)
        XCTAssertEqual(curated.source, .userCustomization)
        XCTAssertEqual(curated.title, "修复本地环境")
        XCTAssertEqual(curated.primaryUsage, "构建工具无法启动")
        XCTAssertTrue(curated.isQuickRunnable)
    }

    func testChangedScriptInvalidatesCustomizedQuickRunApproval() throws {
        try writeScript("scripts/cleanup.sh", body: "echo first")
        let original = try XCTUnwrap(
            LocalActionCatalog.discover(workspace: workspace)
                .first(where: { $0.relativePath == "scripts/cleanup.sh" })
        )
        let customization = LocalActionCustomization(
            action: original,
            title: "清理缓存",
            summary: "清理本地缓存",
            whenToUse: ["缓存损坏"],
            aliases: [],
            risk: .low,
            quickRun: true
        )
        XCTAssertTrue(original.applying(customization).isQuickRunnable)

        try writeScript("scripts/cleanup.sh", body: "echo changed")
        let changed = try XCTUnwrap(
            LocalActionCatalog.discover(workspace: workspace)
                .first(where: { $0.relativePath == "scripts/cleanup.sh" })
        )
        let reviewed = changed.applying(customization)

        XCTAssertTrue(reviewed.quickRunNeedsReview)
        XCTAssertFalse(reviewed.isQuickRunnable)
    }

    func testSavedStateDecodesLegacyPayloadWithoutCustomizations() throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["favoriteIDs": ["fixture"], "history": []]
        )
        let state = try JSONDecoder().decode(LocalActionSavedState.self, from: data)

        XCTAssertEqual(state.favoriteIDs, ["fixture"])
        XCTAssertTrue(state.customizations.isEmpty)
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

    private func writeScript(_ relativePath: String, body: String = "echo ok") throws {
        let url = temporaryDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
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
            modifiedAt: nil,
            contentFingerprint: "fixture-fingerprint",
            quickRunApprovalFingerprint: nil,
            isCustomized: false
        )
    }
}
