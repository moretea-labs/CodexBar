import CryptoKit
import Foundation

enum LocalActionRisk: String, Codable, CaseIterable, Identifiable, Hashable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "需确认"
        case .high: return "高风险"
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.shield"
        case .high: return "exclamationmark.triangle.fill"
        }
    }
}

enum LocalActionSource: String, Codable, Hashable {
    case workspaceManifest
    case sidecarManifest
    case inlineAnnotation
    case discovered
    case userCustomization

    var title: String {
        switch self {
        case .workspaceManifest: return "项目清单"
        case .sidecarManifest: return "脚本清单"
        case .inlineAnnotation: return "脚本注解"
        case .discovered: return "自动发现"
        case .userCustomization: return "已整理"
        }
    }
}

enum LocalActionScope: String, CaseIterable, Identifiable {
    case available
    case favorites
    case recent
    case discovered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: return "可用"
        case .favorites: return "收藏"
        case .recent: return "最近"
        case .discovered: return "已发现"
        }
    }
}

struct LocalAction: Identifiable, Equatable, Hashable {
    let id: String
    let workspaceName: String
    let workspacePath: String
    let scriptPath: String
    let relativePath: String
    let title: String
    let summary: String
    let whenToUse: [String]
    let aliases: [String]
    let risk: LocalActionRisk
    let quickRun: Bool
    let requiresConfirmation: Bool
    let published: Bool
    let source: LocalActionSource
    let workingDirectory: String
    let arguments: [String]
    let modifiedAt: Date?
    let contentFingerprint: String?
    let quickRunApprovalFingerprint: String?
    let isCustomized: Bool

    var quickRunNeedsReview: Bool {
        isCustomized
            && quickRun
            && (contentFingerprint == nil || quickRunApprovalFingerprint != contentFingerprint)
    }

    var isQuickRunnable: Bool {
        published
            && quickRun
            && risk == .low
            && !requiresConfirmation
            && !quickRunNeedsReview
    }

    var commandPreview: String {
        LocalActionInvocation(action: self).commandPreview
    }

    var primaryUsage: String {
        whenToUse.first ?? summary
    }

    func applying(_ customization: LocalActionCustomization) -> LocalAction {
        guard customization.actionID == id else { return self }
        let allowsQuickRun = customization.risk == .low && customization.quickRun
        return LocalAction(
            id: id,
            workspaceName: workspaceName,
            workspacePath: workspacePath,
            scriptPath: scriptPath,
            relativePath: relativePath,
            title: customization.title,
            summary: customization.summary,
            whenToUse: customization.whenToUse,
            aliases: customization.aliases,
            risk: customization.risk,
            quickRun: allowsQuickRun,
            requiresConfirmation: !allowsQuickRun,
            published: true,
            source: .userCustomization,
            workingDirectory: workingDirectory,
            arguments: arguments,
            modifiedAt: modifiedAt,
            contentFingerprint: contentFingerprint,
            quickRunApprovalFingerprint: customization.approvedFingerprint,
            isCustomized: true
        )
    }
}

struct LocalActionCustomization: Codable, Equatable {
    let actionID: String
    var title: String
    var summary: String
    var whenToUse: [String]
    var aliases: [String]
    var risk: LocalActionRisk
    var quickRun: Bool
    var approvedFingerprint: String?
    var updatedAt: Date

    init(
        action: LocalAction,
        title: String,
        summary: String,
        whenToUse: [String],
        aliases: [String],
        risk: LocalActionRisk,
        quickRun: Bool,
        updatedAt: Date = Date()
    ) {
        actionID = action.id
        self.title = title
        self.summary = summary
        self.whenToUse = whenToUse
        self.aliases = aliases
        self.risk = risk
        self.quickRun = risk == .low && quickRun
        approvedFingerprint = self.quickRun ? action.contentFingerprint : nil
        self.updatedAt = updatedAt
    }
}

struct LocalActionRunRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let actionID: String
    let title: String
    let workspaceName: String
    let workspacePath: String
    let relativePath: String
    let startedAt: Date
    let finishedAt: Date
    let exitCode: Int32
    let succeeded: Bool
    let outputTail: String

    init(
        id: UUID = UUID(),
        action: LocalAction,
        startedAt: Date,
        finishedAt: Date,
        exitCode: Int32,
        outputTail: String
    ) {
        self.id = id
        actionID = action.id
        title = action.title
        workspaceName = action.workspaceName
        workspacePath = action.workspacePath
        relativePath = action.relativePath
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        succeeded = exitCode == 0
        self.outputTail = outputTail
    }
}

struct LocalActionSavedState: Codable {
    var favoriteIDs: [String]
    var history: [LocalActionRunRecord]
    var customizations: [String: LocalActionCustomization]

    init(
        favoriteIDs: [String],
        history: [LocalActionRunRecord],
        customizations: [String: LocalActionCustomization] = [:]
    ) {
        self.favoriteIDs = favoriteIDs
        self.history = history
        self.customizations = customizations
    }

    private enum CodingKeys: String, CodingKey {
        case favoriteIDs
        case history
        case customizations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteIDs = try container.decodeIfPresent([String].self, forKey: .favoriteIDs) ?? []
        history = try container.decodeIfPresent([LocalActionRunRecord].self, forKey: .history) ?? []
        customizations = try container.decodeIfPresent(
            [String: LocalActionCustomization].self,
            forKey: .customizations
        ) ?? [:]
    }
}

enum LocalActionPersistenceStore {
    private static let key = "CodexBar.localActions.v1"

    static func load() -> LocalActionSavedState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(LocalActionSavedState.self, from: data) else {
            return LocalActionSavedState(favoriteIDs: [], history: [], customizations: [:])
        }
        return state
    }

    static func save(
        favoriteIDs: Set<String>,
        history: [LocalActionRunRecord],
        customizations: [String: LocalActionCustomization]
    ) {
        let state = LocalActionSavedState(
            favoriteIDs: Array(favoriteIDs).sorted(),
            history: Array(history.prefix(100)),
            customizations: customizations
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct LocalActionManifestFile: Decodable {
    let actions: [LocalActionManifestEntry]
}

private struct LocalActionManifestEntry: Decodable {
    var script: String?
    var title: String?
    var summary: String?
    var whenToUse: [String]?
    var aliases: [String]?
    var risk: LocalActionRisk?
    var quickRun: Bool?
    var requiresConfirmation: Bool?
    var published: Bool?
    var workingDirectory: String?
    var arguments: [String]?
}

private struct InlineActionMetadata {
    var isAction = false
    var title: String?
    var summary: String?
    var whenToUse: [String] = []
    var aliases: [String] = []
    var risk: LocalActionRisk?
    var quickRun: Bool?
    var requiresConfirmation: Bool?
    var published: Bool?
}

enum LocalActionCatalog {
    private static let scriptExtensions: Set<String> = ["sh", "bash", "zsh", "command", "py", "rb"]
    private static let candidateDirectories = ["Scripts", "scripts", "Tools", "tools"]
    private static let excludedDirectories: Set<String> = [
        ".git", ".build", "build", "Build", "DerivedData", "node_modules", "Pods", "vendor"
    ]

    static func discover(workspace: Workspace) -> [LocalAction] {
        let rootURL = URL(fileURLWithPath: workspace.path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }

        var actionsByPath: [String: LocalAction] = [:]

        for entry in loadWorkspaceManifest(rootURL: rootURL) {
            guard let script = entry.script,
                  let scriptURL = safeURL(relativePath: script, rootURL: rootURL),
                  FileManager.default.fileExists(atPath: scriptURL.path),
                  isScript(scriptURL) else { continue }

            let action = makeAction(
                workspace: workspace,
                rootURL: rootURL,
                scriptURL: scriptURL,
                metadata: entry,
                source: .workspaceManifest,
                defaultPublished: true
            )
            actionsByPath[action.relativePath] = action
        }

        var scannedRoots = Set<String>()
        for directoryName in candidateDirectories {
            let directoryURL = rootURL.appendingPathComponent(directoryName, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  scannedRoots.insert(directoryURL.path).inserted else { continue }

            for scriptURL in scanScripts(in: directoryURL) {
                let relativePath = relativePath(for: scriptURL, rootURL: rootURL)
                if actionsByPath[relativePath] != nil { continue }

                if let sidecar = loadSidecar(for: scriptURL) {
                    actionsByPath[relativePath] = makeAction(
                        workspace: workspace,
                        rootURL: rootURL,
                        scriptURL: scriptURL,
                        metadata: sidecar,
                        source: .sidecarManifest,
                        defaultPublished: true
                    )
                    continue
                }

                let inline = loadInlineMetadata(scriptURL)
                if inline.isAction || inline.published == true {
                    actionsByPath[relativePath] = makeAction(
                        workspace: workspace,
                        rootURL: rootURL,
                        scriptURL: scriptURL,
                        inline: inline,
                        source: .inlineAnnotation
                    )
                } else {
                    actionsByPath[relativePath] = fallbackAction(
                        workspace: workspace,
                        rootURL: rootURL,
                        scriptURL: scriptURL
                    )
                }
            }
        }

        return actionsByPath.values.sorted {
            if $0.published != $1.published { return $0.published && !$1.published }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    static func search(
        _ actions: [LocalAction],
        query: String,
        favoriteIDs: Set<String>,
        recentActionIDs: [String]
    ) -> [LocalAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentRanks = Dictionary(uniqueKeysWithValues: recentActionIDs.enumerated().map { ($0.element, $0.offset) })

        if trimmed.isEmpty {
            return actions.sorted { lhs, rhs in
                let lhsFavorite = favoriteIDs.contains(lhs.id)
                let rhsFavorite = favoriteIDs.contains(rhs.id)
                if lhsFavorite != rhsFavorite { return lhsFavorite && !rhsFavorite }

                let lhsRecent = recentRanks[lhs.id] ?? Int.max
                let rhsRecent = recentRanks[rhs.id] ?? Int.max
                if lhsRecent != rhsRecent { return lhsRecent < rhsRecent }

                if lhs.published != rhs.published { return lhs.published && !rhs.published }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }

        let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        return actions.compactMap { action -> (LocalAction, Int)? in
            let title = normalize(action.title)
            let aliases = normalize(action.aliases.joined(separator: " "))
            let usage = normalize(action.whenToUse.joined(separator: " "))
            let summary = normalize(action.summary)
            let path = normalize(action.relativePath)

            var score = 0
            if title == normalized { score += 150 }
            if title.contains(normalized) { score += 100 }
            if aliases.contains(normalized) { score += 85 }
            if usage.contains(normalized) { score += 75 }
            if summary.contains(normalized) { score += 45 }
            if path.contains(normalized) { score += 15 }

            for token in tokens where !token.isEmpty {
                if title.contains(token) { score += 30 }
                if aliases.contains(token) { score += 24 }
                if usage.contains(token) { score += 20 }
                if summary.contains(token) { score += 12 }
                if path.contains(token) { score += 4 }
            }

            if favoriteIDs.contains(action.id) { score += 10 }
            if let rank = recentRanks[action.id] { score += max(1, 8 - rank) }
            if action.published { score += 4 }
            return score > 0 ? (action, score) : nil
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
        }
        .map(\.0)
    }

    private static func loadWorkspaceManifest(rootURL: URL) -> [LocalActionManifestEntry] {
        let url = rootURL.appendingPathComponent(".codexbar/actions.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(LocalActionManifestFile.self, from: data) else {
            return []
        }
        return manifest.actions
    }

    private static func loadSidecar(for scriptURL: URL) -> LocalActionManifestEntry? {
        let candidates = [
            scriptURL.deletingPathExtension().appendingPathExtension("script.json"),
            URL(fileURLWithPath: scriptURL.path + ".script.json")
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let entry = try? JSONDecoder().decode(LocalActionManifestEntry.self, from: data) {
                return entry
            }
        }
        return nil
    }

    private static func loadInlineMetadata(_ scriptURL: URL) -> InlineActionMetadata {
        guard let handle = try? FileHandle(forReadingFrom: scriptURL) else { return InlineActionMetadata() }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 24_000)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return InlineActionMetadata() }

        var metadata = InlineActionMetadata()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(100) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let markerRange = trimmed.range(of: "@") else { continue }
            let annotation = String(trimmed[markerRange.lowerBound...])
            let parts = annotation.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            let key = parts.first.map(String.init)?.lowercased() ?? ""
            let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            switch key {
            case "@action": metadata.isAction = true
            case "@title": metadata.title = emptyToNil(value)
            case "@summary": metadata.summary = emptyToNil(value)
            case "@when-to-use": metadata.whenToUse = splitList(value, separators: ["|", ";"])
            case "@aliases": metadata.aliases = splitList(value, separators: [",", "|", ";"])
            case "@risk": metadata.risk = LocalActionRisk(rawValue: value.lowercased())
            case "@quick-run": metadata.quickRun = parseBool(value)
            case "@confirm": metadata.requiresConfirmation = parseBool(value)
            case "@published": metadata.published = parseBool(value)
            default: break
            }
        }
        return metadata
    }

    private static func makeAction(
        workspace: Workspace,
        rootURL: URL,
        scriptURL: URL,
        metadata: LocalActionManifestEntry,
        source: LocalActionSource,
        defaultPublished: Bool
    ) -> LocalAction {
        let relative = relativePath(for: scriptURL, rootURL: rootURL)
        let workingDirectoryURL: URL
        if let configured = metadata.workingDirectory,
           let safe = safeURL(relativePath: configured, rootURL: rootURL) {
            workingDirectoryURL = safe
        } else {
            workingDirectoryURL = rootURL
        }

        return LocalAction(
            id: stableID(workspacePath: workspace.path, relativePath: relative),
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            scriptPath: scriptURL.path,
            relativePath: relative,
            title: metadata.title ?? displayTitle(scriptURL),
            summary: metadata.summary ?? "执行 \(relative)",
            whenToUse: metadata.whenToUse ?? [],
            aliases: metadata.aliases ?? [],
            risk: metadata.risk ?? .medium,
            quickRun: metadata.quickRun ?? false,
            requiresConfirmation: metadata.requiresConfirmation ?? ((metadata.risk ?? .medium) != .low),
            published: metadata.published ?? defaultPublished,
            source: source,
            workingDirectory: workingDirectoryURL.path,
            arguments: metadata.arguments ?? [],
            modifiedAt: modificationDate(scriptURL),
            contentFingerprint: fileFingerprint(scriptURL),
            quickRunApprovalFingerprint: nil,
            isCustomized: false
        )
    }

    private static func makeAction(
        workspace: Workspace,
        rootURL: URL,
        scriptURL: URL,
        inline: InlineActionMetadata,
        source: LocalActionSource
    ) -> LocalAction {
        let relative = relativePath(for: scriptURL, rootURL: rootURL)
        let risk = inline.risk ?? .medium
        return LocalAction(
            id: stableID(workspacePath: workspace.path, relativePath: relative),
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            scriptPath: scriptURL.path,
            relativePath: relative,
            title: inline.title ?? displayTitle(scriptURL),
            summary: inline.summary ?? "执行 \(relative)",
            whenToUse: inline.whenToUse,
            aliases: inline.aliases,
            risk: risk,
            quickRun: inline.quickRun ?? false,
            requiresConfirmation: inline.requiresConfirmation ?? (risk != .low),
            published: inline.published ?? true,
            source: source,
            workingDirectory: rootURL.path,
            arguments: [],
            modifiedAt: modificationDate(scriptURL),
            contentFingerprint: fileFingerprint(scriptURL),
            quickRunApprovalFingerprint: nil,
            isCustomized: false
        )
    }

    private static func fallbackAction(workspace: Workspace, rootURL: URL, scriptURL: URL) -> LocalAction {
        let relative = relativePath(for: scriptURL, rootURL: rootURL)
        return LocalAction(
            id: stableID(workspacePath: workspace.path, relativePath: relative),
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            scriptPath: scriptURL.path,
            relativePath: relative,
            title: displayTitle(scriptURL),
            summary: "自动发现的脚本，尚未确认用途。",
            whenToUse: [],
            aliases: [],
            risk: .medium,
            quickRun: false,
            requiresConfirmation: true,
            published: false,
            source: .discovered,
            workingDirectory: rootURL.path,
            arguments: [],
            modifiedAt: modificationDate(scriptURL),
            contentFingerprint: fileFingerprint(scriptURL),
            quickRunApprovalFingerprint: nil,
            isCustomized: false
        )
    }

    private static func scanScripts(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isRegularFile == true, isScript(url) {
                results.append(url.standardizedFileURL.resolvingSymlinksInPath())
            }
        }
        return results
    }

    private static func isScript(_ url: URL) -> Bool {
        if scriptExtensions.contains(url.pathExtension.lowercased()) { return true }
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 128)) ?? Data()
        return String(data: data, encoding: .utf8)?.hasPrefix("#!") == true
    }

    private static func safeURL(relativePath: String, rootURL: URL) -> URL? {
        guard !relativePath.hasPrefix("/") else { return nil }
        let candidate = rootURL.appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path == rootURL.path || candidate.path.hasPrefix(rootPath) else { return nil }
        return candidate
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.lastPathComponent
    }

    private static func stableID(workspacePath: String, relativePath: String) -> String {
        workspacePath + "::" + relativePath
    }

    private static func displayTitle(_ url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func fileFingerprint(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func splitList(_ value: String, separators: [Character]) -> [String] {
        value.split(whereSeparator: { separators.contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "1", "on": return true
        case "false", "no", "0", "off": return false
        default: return nil
        }
    }

    private static func emptyToNil(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

struct LocalActionInvocation {
    let executablePath: String
    let arguments: [String]

    init(action: LocalAction) {
        let extensionName = URL(fileURLWithPath: action.scriptPath).pathExtension.lowercased()
        switch extensionName {
        case "sh", "bash":
            executablePath = "/bin/bash"
            arguments = [action.scriptPath] + action.arguments
        case "zsh", "command":
            executablePath = "/bin/zsh"
            arguments = [action.scriptPath] + action.arguments
        case "py":
            executablePath = "/usr/bin/env"
            arguments = ["python3", action.scriptPath] + action.arguments
        case "rb":
            executablePath = "/usr/bin/env"
            arguments = ["ruby", action.scriptPath] + action.arguments
        default:
            if FileManager.default.isExecutableFile(atPath: action.scriptPath) {
                executablePath = action.scriptPath
                arguments = action.arguments
            } else {
                executablePath = "/bin/zsh"
                arguments = [action.scriptPath] + action.arguments
            }
        }
    }

    var commandPreview: String {
        ([executablePath] + arguments).map(ShellUtilities.shellQuote).joined(separator: " ")
    }
}

final class LocalActionRunner {
    private let lock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    func start(
        action: LocalAction,
        onOutput: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Int32, Error>) -> Void
    ) throws {
        lock.lock()
        guard process?.isRunning != true else {
            lock.unlock()
            throw CodexBarError.processAlreadyRunning
        }

        let invocation = LocalActionInvocation(action: action)
        let task = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process = task
        stdoutPipe = stdout
        stderrPipe = stderr
        lock.unlock()

        task.executableURL = URL(fileURLWithPath: invocation.executablePath)
        task.arguments = invocation.arguments
        task.currentDirectoryURL = URL(fileURLWithPath: action.workingDirectory, isDirectory: true)
        task.environment = ProcessInfo.processInfo.environment.merging(["TERM": "dumb"]) { _, new in new }
        task.standardOutput = stdout
        task.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            onOutput(String(decoding: data, as: UTF8.self))
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            onOutput(String(decoding: data, as: UTF8.self))
        }

        task.terminationHandler = { [weak self] process in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            let remainingOutput = stdout.fileHandleForReading.readDataToEndOfFile()
            let remainingError = stderr.fileHandleForReading.readDataToEndOfFile()
            if !remainingOutput.isEmpty { onOutput(String(decoding: remainingOutput, as: UTF8.self)) }
            if !remainingError.isEmpty { onOutput(String(decoding: remainingError, as: UTF8.self)) }

            self?.lock.lock()
            self?.process = nil
            self?.stdoutPipe = nil
            self?.stderrPipe = nil
            self?.lock.unlock()
            onCompletion(.success(process.terminationStatus))
        }

        do {
            try task.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            process = nil
            stdoutPipe = nil
            stderrPipe = nil
            lock.unlock()
            throw error
        }
    }

    func cancel() {
        lock.lock()
        let current = process
        lock.unlock()
        guard current?.isRunning == true else { return }
        current?.terminate()
    }

    deinit {
        cancel()
    }
}
