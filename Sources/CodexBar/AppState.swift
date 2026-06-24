import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let codexBarFocusPrompt = Notification.Name("CodexBar.focusPrompt")
}

@MainActor
final class AppState: ObservableObject {
    @Published var workspaces: [Workspace] {
        didSet { savePreferences() }
    }
    @Published var selectedWorkspaceID: UUID? {
        didSet { savePreferences() }
    }
    @Published var executionMode: ExecutionMode {
        didSet { savePreferences() }
    }
    @Published var hotKeyPreset: HotKeyPreset {
        didSet { savePreferences() }
    }
    @Published var customCodexPath: String {
        didSet { savePreferences() }
    }
    @Published var history: [TaskHistoryItem] {
        didSet { savePreferences() }
    }

    // Session-only UI state. Pinned mode intentionally resets to false on every launch.
    @Published var navigation: AppSection = .compose
    @Published var isPinned = false
    @Published var prompt = ""
    @Published var backgroundTasks: [BackgroundTaskSession] = []
    @Published var selectedTaskID: UUID?
    @Published var statusMessage = ""
    @Published var lastRunSucceeded: Bool?
    @Published var detectedCodexPath: String?
    @Published var isDetectingCodex = false
    @Published var isPresentingSystemPanel = false

    private var runners: [UUID: CodexRunner] = [:]
    private var cancelledTaskIDs = Set<UUID>()
    private var isLoading = true

    init() {
        if let saved = PersistenceStore.load() {
            workspaces = saved.workspaces
            selectedWorkspaceID = saved.selectedWorkspaceID
            // Every launch defaults to background mode, regardless of the last session.
            executionMode = .background
            hotKeyPreset = saved.hotKeyPreset
            customCodexPath = saved.customCodexPath
            history = saved.history
        } else {
            let initial = Self.defaultWorkspace()
            workspaces = [initial]
            selectedWorkspaceID = initial.id
            executionMode = .background
            hotKeyPreset = .optionSpace
            customCodexPath = ""
            history = []
        }

        if selectedWorkspace == nil {
            selectedWorkspaceID = workspaces.first?.id
        }
        isLoading = false
        detectCodex()
    }

    var selectedWorkspace: Workspace? {
        guard let selectedWorkspaceID else { return workspaces.first }
        return workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces.first
    }

    var effectiveCodexPath: String? {
        let custom = customCodexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        return detectedCodexPath
    }

    var selectedTask: BackgroundTaskSession? {
        guard let selectedTaskID else { return backgroundTasks.first }
        return backgroundTasks.first(where: { $0.id == selectedTaskID }) ?? backgroundTasks.first
    }

    var runningTaskCount: Int {
        backgroundTasks.filter { $0.status.isRunning }.count
    }

    var completedTaskCount: Int {
        backgroundTasks.count - runningTaskCount
    }

    var canRun: Bool {
        guard selectedWorkspace != nil, effectiveCodexPath != nil else { return false }
        if executionMode == .background {
            return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    func detectCodex() {
        isDetectingCodex = true
        ExecutableLocator.locateCodex(customPath: customCodexPath) { [weak self] path in
            guard let self else { return }
            self.detectedCodexPath = path
            self.isDetectingCodex = false
            if path == nil {
                self.statusMessage = CodexBarError.codexNotFound.localizedDescription
            } else if self.statusMessage == CodexBarError.codexNotFound.localizedDescription {
                self.statusMessage = ""
            }
        }
    }

    func addWorkspace() {
        isPresentingSystemPanel = true
        defer {
            isPresentingSystemPanel = false
            NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
        }

        let panel = NSOpenPanel()
        panel.title = "添加工作目录"
        panel.prompt = "添加"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let normalized = url.standardizedFileURL.path
        if let existing = workspaces.first(where: { $0.path == normalized }) {
            selectedWorkspaceID = existing.id
            return
        }

        let workspace = Workspace(name: url.lastPathComponent, path: normalized)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
    }

    func removeSelectedWorkspace() {
        guard let selectedWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        workspaces.remove(at: index)
        self.selectedWorkspaceID = workspaces.first?.id
    }

    func revealSelectedWorkspace() {
        guard let selectedWorkspace else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selectedWorkspace.path)])
    }

    func chooseCodexExecutable() {
        isPresentingSystemPanel = true
        defer {
            isPresentingSystemPanel = false
            NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
        }

        let panel = NSOpenPanel()
        panel.title = "选择 Codex 可执行文件"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        customCodexPath = url.path
        detectCodex()
    }

    func selectSection(_ section: AppSection) {
        navigation = section
        if section == .compose {
            NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
        }
    }

    func selectTask(_ id: UUID, openTaskCenter: Bool = false) {
        guard let task = backgroundTasks.first(where: { $0.id == id }) else { return }
        selectedTaskID = id
        switch task.status {
        case .running:
            lastRunSucceeded = nil
            statusMessage = "任务正在执行。"
        case .succeeded:
            lastRunSucceeded = true
            statusMessage = "任务已完成。"
        case .failed:
            lastRunSucceeded = false
            statusMessage = task.errorMessage ?? "任务执行失败。"
        case .cancelled:
            lastRunSucceeded = false
            statusMessage = "任务已停止。"
        }
        if openTaskCenter {
            navigation = .tasks
        }
    }

    func useHistory(_ item: TaskHistoryItem) {
        prompt = item.prompt
        if let workspace = workspaces.first(where: { $0.path == item.workspacePath }) {
            selectedWorkspaceID = workspace.id
        }
        executionMode = item.mode
        navigation = .compose
        NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
    }

    func deleteHistory(_ item: TaskHistoryItem) {
        history.removeAll(where: { $0.id == item.id })
    }

    func clearHistory() {
        history.removeAll()
    }

    func runCurrentTask() {
        statusMessage = ""
        lastRunSucceeded = nil

        guard let workspace = selectedWorkspace,
              FileManager.default.fileExists(atPath: workspace.path) else {
            statusMessage = CodexBarError.invalidWorkspace.localizedDescription
            return
        }
        guard let executablePath = effectiveCodexPath else {
            statusMessage = CodexBarError.codexNotFound.localizedDescription
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if executionMode == .background, trimmedPrompt.isEmpty {
            statusMessage = CodexBarError.emptyPrompt.localizedDescription
            return
        }

        let historyItem = TaskHistoryItem(
            prompt: trimmedPrompt,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            mode: executionMode
        )
        prependHistory(historyItem)

        switch executionMode {
        case .background:
            startBackgroundTask(
                historyItem: historyItem,
                executablePath: executablePath,
                workspace: workspace,
                prompt: trimmedPrompt
            )
        case .terminal:
            do {
                try TerminalLauncher.launch(
                    executablePath: executablePath,
                    workspacePath: workspace.path,
                    initialPrompt: trimmedPrompt
                )
                updateHistory(id: historyItem.id, succeeded: true)
                lastRunSucceeded = true
                statusMessage = "已在 Terminal 中启动 Codex。"
                prompt = ""
            } catch {
                updateHistory(id: historyItem.id, succeeded: false)
                lastRunSucceeded = false
                statusMessage = error.localizedDescription
            }
        }
    }

    func cancelSelectedTask() {
        guard let selectedTaskID else { return }
        cancelTask(id: selectedTaskID)
    }

    func cancelTask(id: UUID) {
        guard let index = backgroundTasks.firstIndex(where: { $0.id == id }),
              backgroundTasks[index].status.isRunning,
              let runner = runners[id] else { return }

        cancelledTaskIDs.insert(id)
        backgroundTasks[index].errorMessage = "正在停止…"
        statusMessage = "正在停止任务…"
        runner.cancel()
    }

    func cancelAllRunningTasks() {
        for task in backgroundTasks where task.status.isRunning {
            cancelTask(id: task.id)
        }
    }

    func removeTask(id: UUID) {
        guard let task = backgroundTasks.first(where: { $0.id == id }),
              !task.status.isRunning else { return }
        backgroundTasks.removeAll(where: { $0.id == id })
        if selectedTaskID == id {
            selectedTaskID = backgroundTasks.first?.id
        }
    }

    func clearCompletedTasks() {
        let completedIDs = Set(backgroundTasks.filter { !$0.status.isRunning }.map(\.id))
        backgroundTasks.removeAll(where: { completedIDs.contains($0.id) })
        if let selectedTaskID, completedIDs.contains(selectedTaskID) {
            self.selectedTaskID = backgroundTasks.first?.id
        }
    }

    private func startBackgroundTask(
        historyItem: TaskHistoryItem,
        executablePath: String,
        workspace: Workspace,
        prompt: String
    ) {
        let taskSession = BackgroundTaskSession(
            historyID: historyItem.id,
            prompt: prompt,
            workspaceName: workspace.name,
            workspacePath: workspace.path
        )
        let runner = CodexRunner()

        backgroundTasks.insert(taskSession, at: 0)
        selectedTaskID = taskSession.id
        runners[taskSession.id] = runner
        trimSessionTasksIfNeeded()

        do {
            try runner.start(
                executablePath: executablePath,
                workspacePath: workspace.path,
                prompt: prompt,
                onEventLine: { [weak self] line in
                    self?.handleEventLine(line, for: taskSession.id)
                },
                onDiagnostic: { [weak self] line in
                    self?.appendDiagnostic(line, to: taskSession.id)
                },
                onCompletion: { [weak self] result in
                    self?.finishTask(id: taskSession.id, result: result)
                }
            )
            self.prompt = ""
            statusMessage = runningTaskCount > 1
                ? "任务已启动，当前有 \(runningTaskCount) 个后台任务执行中。"
                : "任务已启动，可继续创建其他任务。"
        } catch {
            runners[taskSession.id] = nil
            markTaskLaunchFailure(id: taskSession.id, error: error)
        }
    }

    private func handleEventLine(_ line: String, for id: UUID) {
        guard let index = backgroundTasks.firstIndex(where: { $0.id == id }) else { return }
        let mutation = CodexJSONEventParser.parse(line: line)

        switch mutation {
        case .threadStarted(let threadID):
            if !threadID.isEmpty {
                backgroundTasks[index].threadID = threadID
            }
        case .turnStarted:
            upsertBlock(
                CodexOutputBlock(
                    id: "turn-started",
                    kind: .lifecycle,
                    title: "Codex 已开始处理",
                    status: .inProgress
                ),
                at: index
            )
        case .upsert(let block):
            upsertBlock(block, at: index)
        case .append(let block):
            backgroundTasks[index].blocks.append(block)
        case .turnCompleted(let usage):
            backgroundTasks[index].usage = usage
            backgroundTasks[index].blocks.removeAll(where: { $0.id == "turn-started" })
            backgroundTasks[index].blocks.append(
                CodexOutputBlock(
                    kind: .lifecycle,
                    title: "任务处理完成",
                    detail: usage?.summary ?? "",
                    status: .completed
                )
            )
        case .turnFailed(let message):
            backgroundTasks[index].blocks.removeAll(where: { $0.id == "turn-started" })
            backgroundTasks[index].blocks.append(
                CodexOutputBlock(
                    kind: .error,
                    title: "任务执行失败",
                    body: message,
                    status: .failed
                )
            )
            backgroundTasks[index].errorMessage = message
        case .ignored:
            return
        }

        backgroundTasks[index].outputRevision += 1
    }

    private func appendDiagnostic(_ line: String, to id: UUID) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = backgroundTasks.firstIndex(where: { $0.id == id }) else { return }

        // Coalesce adjacent stderr lines to keep warnings readable without
        // generating one card per line.
        if let lastIndex = backgroundTasks[index].blocks.indices.last,
           backgroundTasks[index].blocks[lastIndex].kind == .diagnostic {
            if !backgroundTasks[index].blocks[lastIndex].body.isEmpty {
                backgroundTasks[index].blocks[lastIndex].body.append("\n")
            }
            backgroundTasks[index].blocks[lastIndex].body.append(trimmed)
        } else {
            backgroundTasks[index].blocks.append(
                CodexOutputBlock(
                    kind: .diagnostic,
                    title: "运行信息",
                    body: trimmed
                )
            )
        }
        backgroundTasks[index].outputRevision += 1
    }

    private func upsertBlock(_ block: CodexOutputBlock, at taskIndex: Int) {
        if let blockIndex = backgroundTasks[taskIndex].blocks.firstIndex(where: { $0.id == block.id }) {
            backgroundTasks[taskIndex].blocks[blockIndex] = block
        } else {
            backgroundTasks[taskIndex].blocks.append(block)
        }
    }

    private func finishTask(id: UUID, result: Result<Int32, Error>) {
        guard let index = backgroundTasks.firstIndex(where: { $0.id == id }) else {
            runners[id] = nil
            cancelledTaskIDs.remove(id)
            return
        }

        let wasCancelled = cancelledTaskIDs.remove(id) != nil
        runners[id] = nil
        backgroundTasks[index].finishedAt = Date()

        if wasCancelled {
            backgroundTasks[index].blocks.removeAll(where: { $0.id == "turn-started" })
            backgroundTasks[index].status = .cancelled
            backgroundTasks[index].errorMessage = "任务已停止。"
            backgroundTasks[index].blocks.append(
                CodexOutputBlock(
                    kind: .lifecycle,
                    title: "任务已停止",
                    status: .failed
                )
            )
            backgroundTasks[index].outputRevision += 1
            updateHistory(id: backgroundTasks[index].historyID, succeeded: false)
            if selectedTaskID == id {
                lastRunSucceeded = false
                statusMessage = "任务已停止。"
            }
            return
        }

        switch result {
        case .success(let code):
            backgroundTasks[index].exitCode = code
            let succeeded = code == 0
            backgroundTasks[index].status = succeeded ? .succeeded : .failed
            if !succeeded {
                backgroundTasks[index].blocks.removeAll(where: { $0.id == "turn-started" })
                let message = "Codex 已退出，状态码：\(code)"
                backgroundTasks[index].errorMessage = message
                if !backgroundTasks[index].blocks.contains(where: { $0.kind == .error }) {
                    backgroundTasks[index].blocks.append(
                        CodexOutputBlock(
                            kind: .error,
                            title: "进程异常退出",
                            body: message,
                            status: .failed,
                            exitCode: Int(code)
                        )
                    )
                    backgroundTasks[index].outputRevision += 1
                }
            } else if !backgroundTasks[index].blocks.contains(where: { $0.kind == .lifecycle && $0.title == "任务处理完成" }) {
                backgroundTasks[index].blocks.removeAll(where: { $0.id == "turn-started" })
                backgroundTasks[index].blocks.append(
                    CodexOutputBlock(
                        kind: .lifecycle,
                        title: "任务处理完成",
                        status: .completed
                    )
                )
                backgroundTasks[index].outputRevision += 1
            }
            updateHistory(id: backgroundTasks[index].historyID, succeeded: succeeded)
            if selectedTaskID == id {
                lastRunSucceeded = succeeded
                statusMessage = succeeded ? "任务已完成。" : "Codex 已退出，状态码：\(code)"
            }
        case .failure(let error):
            backgroundTasks[index].blocks.removeAll(where: { $0.id == "turn-started" })
            backgroundTasks[index].status = .failed
            backgroundTasks[index].errorMessage = error.localizedDescription
            backgroundTasks[index].blocks.append(
                CodexOutputBlock(
                    kind: .error,
                    title: "任务执行失败",
                    body: error.localizedDescription,
                    status: .failed
                )
            )
            backgroundTasks[index].outputRevision += 1
            updateHistory(id: backgroundTasks[index].historyID, succeeded: false)
            if selectedTaskID == id {
                lastRunSucceeded = false
                statusMessage = error.localizedDescription
            }
        }
    }

    private func markTaskLaunchFailure(id: UUID, error: Error) {
        guard let index = backgroundTasks.firstIndex(where: { $0.id == id }) else { return }
        backgroundTasks[index].status = .failed
        backgroundTasks[index].finishedAt = Date()
        backgroundTasks[index].errorMessage = error.localizedDescription
        backgroundTasks[index].blocks.append(
            CodexOutputBlock(
                kind: .error,
                title: "无法启动 Codex",
                body: error.localizedDescription,
                status: .failed
            )
        )
        backgroundTasks[index].outputRevision += 1
        updateHistory(id: backgroundTasks[index].historyID, succeeded: false)
        lastRunSucceeded = false
        statusMessage = error.localizedDescription
    }

    private func trimSessionTasksIfNeeded() {
        let maximumTasks = 30
        guard backgroundTasks.count > maximumTasks else { return }

        while backgroundTasks.count > maximumTasks,
              let index = backgroundTasks.lastIndex(where: { !$0.status.isRunning }) {
            let id = backgroundTasks[index].id
            backgroundTasks.remove(at: index)
            if selectedTaskID == id {
                selectedTaskID = backgroundTasks.first?.id
            }
        }
    }

    private func prependHistory(_ item: TaskHistoryItem) {
        history.insert(item, at: 0)
        history = Array(history.prefix(100))
    }

    private func updateHistory(id: UUID, succeeded: Bool) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].succeeded = succeeded
    }

    private func savePreferences() {
        guard !isLoading else { return }
        let preferences = PersistedPreferences(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            executionMode: executionMode,
            hotKeyPreset: hotKeyPreset,
            customCodexPath: customCodexPath,
            history: history
        )
        PersistenceStore.save(preferences)
    }

    private static func defaultWorkspace() -> Workspace {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["Developer", "Projects", "Code"]
        for candidate in candidates {
            let url = home.appendingPathComponent(candidate, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return Workspace(name: candidate, path: url.path)
            }
        }
        return Workspace(name: home.lastPathComponent, path: home.path)
    }
}
