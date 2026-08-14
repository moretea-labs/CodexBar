import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let codexBarFocusPrompt = Notification.Name("CodexBar.focusPrompt")
}

@MainActor
final class AppState: ObservableObject {
    @Published var workspaces: [Workspace] {
        didSet {
            savePreferences()
            refreshLocalActionsIfReady()
        }
    }
    @Published var selectedWorkspaceID: UUID? {
        didSet {
            savePreferences()
            refreshLocalActionsIfReady()
        }
    }
    @Published var executionMode: ExecutionMode {
        didSet { savePreferences() }
    }
    @Published var hotKeyPreset: HotKeyPreset {
        didSet { savePreferences() }
    }
    @Published var selectedAgentID: AgentKind {
        didSet { savePreferences() }
    }
    @Published var agentCustomPaths: [String: String] {
        didSet { savePreferences() }
    }
    @Published var terminalTemplate: String {
        didSet { savePreferences() }
    }
    @Published var chatGPTPromptPrefix: String {
        didSet { savePreferences() }
    }
    @Published var history: [TaskHistoryItem] {
        didSet { savePreferences() }
    }

    @Published var localActions: [LocalAction] = []
    @Published var localActionFavoriteIDs: Set<String> = []
    @Published var localActionHistory: [LocalActionRunRecord] = []
    @Published var localActionCustomizations: [String: LocalActionCustomization] = [:]
    @Published var runningLocalActionID: String?
    @Published var localActionRunOutput = ""
    @Published var localActionStatusMessage = ""
    @Published var lastLocalActionSucceeded: Bool?
    @Published var isDiscoveringLocalActions = false
    @Published var localActionsMode: LocalActionsMode = .browse

    @Published var shellCommandHistory: [ShellCommandRecord] = []
    @Published var runningShellCommand: String?
    @Published var lastShellCommand: String?
    @Published var shellCommandOutput = ""
    @Published var shellCommandStatusMessage = ""
    @Published var lastShellCommandSucceeded: Bool?

    // Session-only UI state. Pinned and expanded modes intentionally reset on every launch.
    @Published var navigation: AppSection = .compose
    @Published var isPinned = false
    @Published var isExpanded = false
    @Published var prompt = ""
    @Published var taskIntent: AgentTaskIntent = .execute {
        didSet {
            if taskIntent == .plan {
                executionMode = .background
            }
        }
    }
    @Published var backgroundTasks: [BackgroundTaskSession] = []
    @Published var selectedTaskID: UUID?
    @Published var pendingResumeThreadID: String?
    @Published var statusMessage = ""
    @Published var lastRunSucceeded: Bool?
    @Published var detectedAgentPaths: [String: String] = [:]
    @Published var isDetectingAgents = false
    @Published var isPresentingSystemPanel = false

    private var runners: [UUID: AgentRunner] = [:]
    private var parsers: [UUID: AgentOutputParsing] = [:]
    private var cancelledTaskIDs = Set<UUID>()
    private var localActionRunner: LocalActionRunner?
    private var shellCommandRunner: ShellCommandRunner?
    private var shellCommandWasCancelled = false
    private var localActionDiscoveryGeneration = 0
    private var isLoading = true

    init() {
        if let saved = PersistenceStore.load() {
            workspaces = saved.workspaces
            selectedWorkspaceID = saved.selectedWorkspaceID
            // Every launch defaults to background mode, regardless of the last session.
            executionMode = .background
            hotKeyPreset = saved.hotKeyPreset
            selectedAgentID = saved.agentSelectionVersion < 1 ? .chatgpt : saved.selectedAgentID
            agentCustomPaths = saved.agentCustomPaths
            terminalTemplate = saved.terminalTemplate
            chatGPTPromptPrefix = saved.chatGPTPromptPrefix
            history = saved.history
        } else {
            let initial = Self.defaultWorkspace()
            workspaces = [initial]
            selectedWorkspaceID = initial.id
            executionMode = .background
            hotKeyPreset = .optionSpace
            selectedAgentID = .chatgpt
            agentCustomPaths = [:]
            terminalTemplate = TerminalTemplate.defaultSource
            chatGPTPromptPrefix = ChatGPTLauncher.defaultPromptPrefix
            history = []
        }

        let localActionState = LocalActionPersistenceStore.load()
        localActionFavoriteIDs = Set(localActionState.favoriteIDs)
        localActionHistory = localActionState.history
        localActionCustomizations = localActionState.customizations
        shellCommandHistory = ShellCommandPersistenceStore.load()

        if selectedWorkspace == nil {
            selectedWorkspaceID = workspaces.first?.id
        }
        isLoading = false
        detectAgents()
        refreshLocalActions()
    }

    var selectedWorkspace: Workspace? {
        guard let selectedWorkspaceID else { return workspaces.first }
        return workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces.first
    }

    var selectedAgent: AgentKind { selectedAgentID }

    func effectiveAgentPath(for agent: AgentKind) -> String? {
        let custom = (agentCustomPaths[agent.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        return detectedAgentPaths[agent.rawValue]
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

    var availableLocalActions: [LocalAction] {
        localActions.filter(\.published)
    }

    /// Unpublished scripts awaiting curation (the "整理" step).
    var pendingLocalActions: [LocalAction] {
        localActions.filter { !$0.published }
    }

    /// Customized one-click operations whose backing script changed.
    var reviewLocalActions: [LocalAction] {
        localActions.filter(\.quickRunNeedsReview)
    }

    var recentLocalActionIDs: [String] {
        let workspacePath = selectedWorkspace?.path
        var seen = Set<String>()
        return localActionHistory.compactMap { record in
            guard record.workspacePath == workspacePath,
                  seen.insert(record.actionID).inserted else { return nil }
            return record.actionID
        }
    }

    var recentQuickActions: [LocalAction] {
        let actionsByID = Dictionary(uniqueKeysWithValues: localActions.map { ($0.id, $0) })
        return recentLocalActionIDs.compactMap { actionsByID[$0] }.filter(\.isQuickRunnable)
    }

    var runningLocalAction: LocalAction? {
        guard let runningLocalActionID else { return nil }
        return localActions.first(where: { $0.id == runningLocalActionID })
    }

    var isShellCommandInput: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(">")
    }

    var parsedShellCommand: String? {
        ShellCommandPolicy.command(from: prompt)
    }

    var shellCommandAssessment: ShellCommandAssessment? {
        guard let command = parsedShellCommand, !command.isEmpty else { return nil }
        return ShellCommandPolicy.assess(command)
    }

    var recentShellCommands: [ShellCommandRecord] {
        let workspacePath = selectedWorkspace?.path
        var seen = Set<String>()
        return shellCommandHistory.filter { record in
            guard record.workspacePath == workspacePath else { return false }
            return seen.insert(record.command).inserted
        }
    }

    var canSubmitLauncherInput: Bool {
        if let command = parsedShellCommand {
            return selectedWorkspace != nil
                && !command.isEmpty
                && runningShellCommand == nil
        }
        return canRun
    }

    var isContinuingCodexSession: Bool {
        selectedAgentID == .codex && pendingResumeThreadID != nil
    }

    var canRun: Bool {
        let hasPrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if selectedAgentID == .chatgpt {
            return hasPrompt
        }
        guard selectedWorkspace != nil, effectiveAgentPath(for: selectedAgentID) != nil else { return false }
        if taskIntent == .plan || pendingResumeThreadID != nil || executionMode == .background {
            return hasPrompt
        }
        return true
    }

    func detectAgents() {
        isDetectingAgents = true
        let agents = AgentKind.localAgents
        var completed = 0
        for agent in agents {
            locateAgent(agent) { [weak self] _ in
                guard let self else { return }
                completed += 1
                guard completed == agents.count else { return }
                self.isDetectingAgents = false
                guard self.selectedAgentID.usesLocalExecutable else { return }
                if self.effectiveAgentPath(for: self.selectedAgentID) == nil {
                    self.statusMessage = CodexBarError.agentNotFound(self.selectedAgentID).localizedDescription
                } else if self.statusMessage == CodexBarError.agentNotFound(self.selectedAgentID).localizedDescription {
                    self.statusMessage = ""
                }
            }
        }
    }

    func detectAgent(_ agent: AgentKind) {
        guard agent.usesLocalExecutable else { return }
        locateAgent(agent) { _ in }
    }

    private func locateAgent(_ agent: AgentKind, completion: @escaping (String?) -> Void) {
        ExecutableLocator.locateExecutable(
            name: agent.commandName,
            customPath: agentCustomPaths[agent.rawValue] ?? ""
        ) { [weak self] path in
            guard let self else { return }
            self.detectedAgentPaths[agent.rawValue] = path
            completion(path)
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

    func chooseExecutable(for agent: AgentKind) {
        isPresentingSystemPanel = true
        defer {
            isPresentingSystemPanel = false
            NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
        }

        let panel = NSOpenPanel()
        panel.title = "选择 \(agent.title) 可执行文件"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        agentCustomPaths[agent.rawValue] = url.path
        detectAgent(agent)
    }

    func showCompactLauncher() {
        navigation = .compose
        isExpanded = false
        NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
    }

    func showExpanded(_ section: AppSection = .compose) {
        navigation = section
        isExpanded = true
        if section == .actions {
            refreshLocalActions()
        }
        if section == .compose {
            NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
        }
    }

    func collapseLauncher() {
        showCompactLauncher()
    }

    func selectSection(_ section: AppSection) {
        showExpanded(section)
    }

    func refreshLocalActions() {
        localActionDiscoveryGeneration += 1
        let generation = localActionDiscoveryGeneration

        guard let workspace = selectedWorkspace else {
            localActions = []
            isDiscoveringLocalActions = false
            return
        }

        isDiscoveringLocalActions = true
        let customizations = localActionCustomizations
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let actions = LocalActionCatalog.discover(workspace: workspace).map { action in
                guard let customization = customizations[action.id] else { return action }
                return action.applying(customization)
            }
            DispatchQueue.main.async {
                guard let self,
                      generation == self.localActionDiscoveryGeneration,
                      self.selectedWorkspace?.path == workspace.path else { return }
                self.localActions = actions
                self.isDiscoveringLocalActions = false
            }
        }
    }

    func searchLocalActions(matching query: String) -> [LocalAction] {
        LocalActionCatalog.search(
            availableLocalActions,
            query: query,
            favoriteIDs: localActionFavoriteIDs,
            recentActionIDs: recentLocalActionIDs
        )
    }

    func toggleLocalActionFavorite(_ action: LocalAction) {
        if localActionFavoriteIDs.contains(action.id) {
            localActionFavoriteIDs.remove(action.id)
        } else {
            localActionFavoriteIDs.insert(action.id)
        }
        saveLocalActionState()
    }

    func saveLocalActionCustomization(_ customization: LocalActionCustomization) {
        localActionCustomizations[customization.actionID] = customization
        saveLocalActionState()
        refreshLocalActions()
    }

    func removeLocalActionCustomization(for action: LocalAction) {
        localActionCustomizations.removeValue(forKey: action.id)
        saveLocalActionState()
        refreshLocalActions()
    }

    func runLocalAction(id: String) {
        guard let action = localActions.first(where: { $0.id == id }) else { return }
        runLocalAction(action)
    }

    func runLocalAction(_ action: LocalAction) {
        guard runningLocalActionID == nil else {
            localActionStatusMessage = "已有项目操作正在执行。"
            return
        }
        guard FileManager.default.fileExists(atPath: action.scriptPath) else {
            localActionStatusMessage = "脚本已不存在，请刷新项目操作。"
            lastLocalActionSucceeded = false
            return
        }
        guard FileManager.default.fileExists(atPath: action.workingDirectory) else {
            localActionStatusMessage = "工作目录已不存在。"
            lastLocalActionSucceeded = false
            return
        }

        let runner = LocalActionRunner()
        let startedAt = Date()
        localActionRunner = runner
        runningLocalActionID = action.id
        localActionRunOutput = ""
        localActionStatusMessage = "正在执行“\(action.title)”…"
        lastLocalActionSucceeded = nil

        do {
            try runner.start(
                action: action,
                onOutput: { [weak self] chunk in
                    DispatchQueue.main.async {
                        self?.appendLocalActionOutput(chunk)
                    }
                },
                onCompletion: { [weak self] result in
                    DispatchQueue.main.async {
                        self?.finishLocalAction(action, startedAt: startedAt, result: result)
                    }
                }
            )
        } catch {
            localActionRunner = nil
            runningLocalActionID = nil
            lastLocalActionSucceeded = false
            localActionStatusMessage = error.localizedDescription
        }
    }

    func cancelRunningLocalAction() {
        guard runningLocalActionID != nil else { return }
        localActionStatusMessage = "正在停止项目操作…"
        localActionRunner?.cancel()
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
        pendingResumeThreadID = nil
        prompt = item.prompt
        if let workspace = workspaces.first(where: { $0.path == item.workspacePath }) {
            selectedWorkspaceID = workspace.id
        }
        taskIntent = item.intent
        executionMode = item.intent == .plan ? .background : item.mode
        selectedAgentID = item.agent
        navigation = .compose
        NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
    }

    func openHistory(_ item: TaskHistoryItem) {
        if let existing = backgroundTasks.first(where: { $0.historyID == item.id }) {
            selectTask(existing.id, openTaskCenter: true)
            return
        }
        guard item.transcriptAvailable,
              let transcript = TaskHistoryTranscriptStore.load(for: item.id) else {
            useHistory(item)
            return
        }

        let task = BackgroundTaskSession(
            historyID: item.id,
            prompt: item.prompt,
            workspaceName: item.workspaceName,
            workspacePath: item.workspacePath,
            agent: item.agent,
            intent: item.intent,
            createdAt: item.createdAt,
            finishedAt: transcript.finishedAt,
            threadID: item.threadID,
            blocks: transcript.blocks,
            outputRevision: transcript.blocks.count,
            usage: transcript.usage,
            status: transcript.status,
            exitCode: transcript.exitCode,
            errorMessage: transcript.errorMessage
        )
        backgroundTasks.insert(task, at: 0)
        selectedTaskID = task.id
        trimSessionTasksIfNeeded()
        navigation = .tasks
    }

    func continueHistory(_ item: TaskHistoryItem) {
        guard item.agent == .codex,
              let threadID = item.threadID,
              !threadID.isEmpty else {
            statusMessage = "这条历史没有可继续的 Codex 会话 ID。"
            return
        }
        if let workspace = workspaces.first(where: { $0.path == item.workspacePath }) {
            selectedWorkspaceID = workspace.id
        }
        selectedAgentID = .codex
        taskIntent = .execute
        executionMode = .background
        pendingResumeThreadID = threadID
        prompt = ""
        navigation = .compose
        statusMessage = "继续 Codex 会话：请输入下一条指令。"
        NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
    }

    func cancelPendingResume() {
        pendingResumeThreadID = nil
        statusMessage = ""
    }

    func sendCurrentPromptToChatGPT() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        statusMessage = "正在用 Chrome 打开 ChatGPT…"
        lastRunSucceeded = nil
        ChatGPTLauncher.open(prompt: trimmed, prefix: chatGPTPromptPrefix) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.submitted):
                self.prompt = ""
                self.lastRunSucceeded = true
                self.statusMessage = "已在日常 Chrome 新建 ChatGPT 会话并提交指令。"
            case .success(.prefilledNeedsAccessibility):
                self.lastRunSucceeded = nil
                self.statusMessage = "已在 Chrome 新建会话并填入指令；授权辅助功能后可保证自动提交。"
            case .failure(let error):
                self.lastRunSucceeded = false
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func deleteHistory(_ item: TaskHistoryItem) {
        TaskHistoryTranscriptStore.delete(for: item.id)
        history.removeAll(where: { $0.id == item.id })
    }

    func clearHistory() {
        TaskHistoryTranscriptStore.clear()
        history.removeAll()
    }

    func runShellCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            shellCommandStatusMessage = CodexBarError.emptyCommand.localizedDescription
            lastShellCommandSucceeded = false
            return
        }
        guard ShellCommandPolicy.assess(trimmed).risk != .terminalOnly else {
            shellCommandStatusMessage = "该命令只能在 Terminal 中执行。"
            lastShellCommandSucceeded = false
            return
        }
        guard runningShellCommand == nil else {
            shellCommandStatusMessage = "已有本地命令正在执行。"
            return
        }
        guard let workspace = selectedWorkspace,
              FileManager.default.fileExists(atPath: workspace.path) else {
            shellCommandStatusMessage = CodexBarError.invalidWorkspace.localizedDescription
            lastShellCommandSucceeded = false
            return
        }

        let runner = ShellCommandRunner()
        let startedAt = Date()
        shellCommandRunner = runner
        shellCommandWasCancelled = false
        runningShellCommand = trimmed
        lastShellCommand = trimmed
        shellCommandOutput = ""
        shellCommandStatusMessage = "正在执行命令…"
        lastShellCommandSucceeded = nil

        do {
            try runner.start(
                command: trimmed,
                workspacePath: workspace.path,
                onOutput: { [weak self] chunk in
                    self?.appendShellCommandOutput(chunk)
                },
                onCompletion: { [weak self] result in
                    self?.finishShellCommand(
                        trimmed,
                        workspace: workspace,
                        startedAt: startedAt,
                        result: result
                    )
                }
            )
            prompt = ""
        } catch {
            shellCommandRunner = nil
            runningShellCommand = nil
            shellCommandStatusMessage = error.localizedDescription
            lastShellCommandSucceeded = false
        }
    }

    func cancelRunningShellCommand() {
        guard runningShellCommand != nil else { return }
        shellCommandWasCancelled = true
        shellCommandStatusMessage = "正在停止命令…"
        shellCommandRunner?.cancel()
    }

    func openShellCommandInTerminal(_ command: String) {
        guard let workspace = selectedWorkspace,
              FileManager.default.fileExists(atPath: workspace.path) else {
            shellCommandStatusMessage = CodexBarError.invalidWorkspace.localizedDescription
            lastShellCommandSucceeded = false
            return
        }
        do {
            try TerminalLauncher.launchCommand(
                command: command,
                workspacePath: workspace.path,
                template: TerminalTemplate(source: terminalTemplate)
            )
            lastShellCommand = command
            shellCommandStatusMessage = "已在所选终端中打开命令。"
            lastShellCommandSucceeded = true
            prompt = ""
        } catch {
            shellCommandStatusMessage = error.localizedDescription
            lastShellCommandSucceeded = false
        }
    }

    func reuseShellCommand(_ command: String) {
        prompt = "> " + command
        showCompactLauncher()
    }

    func clearShellCommandResult() {
        guard runningShellCommand == nil else { return }
        shellCommandOutput = ""
        shellCommandStatusMessage = ""
        lastShellCommand = nil
        lastShellCommandSucceeded = nil
    }

    func runCurrentTask() {
        statusMessage = ""
        lastRunSucceeded = nil

        if selectedAgentID == .chatgpt {
            sendCurrentPromptToChatGPT()
            return
        }

        guard let workspace = selectedWorkspace,
              FileManager.default.fileExists(atPath: workspace.path) else {
            statusMessage = CodexBarError.invalidWorkspace.localizedDescription
            return
        }
        guard let executablePath = effectiveAgentPath(for: selectedAgentID) else {
            statusMessage = CodexBarError.agentNotFound(selectedAgentID).localizedDescription
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let resumeSessionID = selectedAgentID == .codex ? pendingResumeThreadID : nil
        let effectiveExecutionMode: ExecutionMode = (taskIntent == .plan || resumeSessionID != nil)
            ? .background
            : executionMode
        if executionMode != effectiveExecutionMode {
            executionMode = effectiveExecutionMode
        }
        if effectiveExecutionMode == .background, trimmedPrompt.isEmpty {
            statusMessage = CodexBarError.emptyPrompt.localizedDescription
            return
        }
        let historyItem = TaskHistoryItem(
            prompt: trimmedPrompt,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            mode: effectiveExecutionMode,
            agent: selectedAgentID,
            intent: taskIntent,
            threadID: resumeSessionID
        )
        prependHistory(historyItem)

        switch effectiveExecutionMode {
        case .background:
            startBackgroundTask(
                historyItem: historyItem,
                executablePath: executablePath,
                workspace: workspace,
                prompt: trimmedPrompt,
                resumeSessionID: resumeSessionID
            )
            pendingResumeThreadID = nil
        case .terminal:
            do {
                try TerminalLauncher.launch(
                    agent: selectedAgentID,
                    executablePath: executablePath,
                    workspacePath: workspace.path,
                    initialPrompt: trimmedPrompt,
                    template: TerminalTemplate(source: terminalTemplate)
                )
                updateHistory(id: historyItem.id, succeeded: true)
                lastRunSucceeded = true
                statusMessage = "已在所选终端中启动 \(selectedAgentID.title)。"
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
        cancelRunningLocalAction()
        cancelRunningShellCommand()
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
        prompt: String,
        resumeSessionID: String?
    ) {
        let agent = historyItem.agent
        let taskSession = BackgroundTaskSession(
            historyID: historyItem.id,
            prompt: prompt,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            agent: agent,
            intent: historyItem.intent,
            threadID: resumeSessionID
        )
        let runner = AgentRunner()
        let parser = AgentParserRegistry.parser(for: agent)
        let plan = AgentCommandFactory.backgroundPlan(
            agent: agent,
            executablePath: executablePath,
            workspacePath: workspace.path,
            prompt: prompt,
            intent: historyItem.intent,
            resumeSessionID: resumeSessionID
        )

        backgroundTasks.insert(taskSession, at: 0)
        selectedTaskID = taskSession.id
        runners[taskSession.id] = runner
        parsers[taskSession.id] = parser
        trimSessionTasksIfNeeded()

        do {
            try runner.start(
                shellCommand: plan.shellCommand,
                stdinPrompt: plan.stdinPrompt,
                workspacePath: workspace.path,
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
            parsers[taskSession.id] = nil
            markTaskLaunchFailure(id: taskSession.id, error: error)
        }
    }

    private func handleEventLine(_ line: String, for id: UUID) {
        guard let index = backgroundTasks.firstIndex(where: { $0.id == id }) else { return }
        let mutation = parsers[id]?.parse(line) ?? .ignored

        switch mutation {
        case .threadStarted(let threadID):
            if !threadID.isEmpty {
                backgroundTasks[index].threadID = threadID
                updateHistoryThreadID(id: backgroundTasks[index].historyID, threadID: threadID)
            }
        case .turnStarted:
            upsertBlock(
                CodexOutputBlock(
                    id: "turn-started",
                    kind: .lifecycle,
                    title: "\(backgroundTasks[index].agent.title) 已开始处理",
                    status: .inProgress
                ),
                at: index
            )
        case .upsert(let block):
            upsertBlock(block, at: index)
        case .append(let block):
            backgroundTasks[index].blocks.append(block)
        case .appendText(let text, let blockID):
            if let blockIndex = backgroundTasks[index].blocks.firstIndex(where: { $0.id == blockID }) {
                backgroundTasks[index].blocks[blockIndex].body.append(text)
            }
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
            parsers[id] = nil
            cancelledTaskIDs.remove(id)
            return
        }

        let agent = backgroundTasks[index].agent
        let wasCancelled = cancelledTaskIDs.remove(id) != nil
        runners[id] = nil
        parsers[id] = nil
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
            syncHistoryTranscript(from: backgroundTasks[index])
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
                let message = "\(agent.title) 已退出，状态码：\(code)"
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
            syncHistoryTranscript(from: backgroundTasks[index])
            if selectedTaskID == id {
                lastRunSucceeded = succeeded
                statusMessage = succeeded ? "任务已完成。" : "\(agent.title) 已退出，状态码：\(code)"
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
            syncHistoryTranscript(from: backgroundTasks[index])
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
                title: "无法启动 \(backgroundTasks[index].agent.title)",
                body: error.localizedDescription,
                status: .failed
            )
        )
        backgroundTasks[index].outputRevision += 1
        updateHistory(id: backgroundTasks[index].historyID, succeeded: false)
        syncHistoryTranscript(from: backgroundTasks[index])
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

    private func refreshLocalActionsIfReady() {
        guard !isLoading else { return }
        refreshLocalActions()
    }

    private func appendShellCommandOutput(_ chunk: String) {
        shellCommandOutput.append(chunk)
        if shellCommandOutput.count > 120_000 {
            shellCommandOutput = String(shellCommandOutput.suffix(100_000))
        }
    }

    private func finishShellCommand(
        _ command: String,
        workspace: Workspace,
        startedAt: Date,
        result: Result<Int32, Error>
    ) {
        shellCommandRunner = nil
        runningShellCommand = nil
        let finishedAt = Date()

        switch result {
        case .success(let exitCode):
            let record = ShellCommandRecord(
                command: command,
                workspaceName: workspace.name,
                workspacePath: workspace.path,
                startedAt: startedAt,
                finishedAt: finishedAt,
                exitCode: exitCode,
                outputTail: String(shellCommandOutput.suffix(20_000))
            )
            shellCommandHistory.insert(record, at: 0)
            shellCommandHistory = Array(shellCommandHistory.prefix(100))
            ShellCommandPersistenceStore.save(shellCommandHistory)

            if shellCommandWasCancelled {
                lastShellCommandSucceeded = false
                shellCommandStatusMessage = "命令已停止。"
            } else {
                lastShellCommandSucceeded = exitCode == 0
                shellCommandStatusMessage = exitCode == 0
                    ? "命令执行成功。"
                    : "命令执行失败，状态码：\(exitCode)"
            }
        case .failure(let error):
            lastShellCommandSucceeded = false
            shellCommandStatusMessage = error.localizedDescription
        }
        shellCommandWasCancelled = false
    }

    private func appendLocalActionOutput(_ chunk: String) {
        localActionRunOutput.append(chunk)
        if localActionRunOutput.count > 120_000 {
            localActionRunOutput = String(localActionRunOutput.suffix(100_000))
        }
    }

    private func finishLocalAction(
        _ action: LocalAction,
        startedAt: Date,
        result: Result<Int32, Error>
    ) {
        localActionRunner = nil
        runningLocalActionID = nil
        let finishedAt = Date()

        switch result {
        case .success(let exitCode):
            let record = LocalActionRunRecord(
                action: action,
                startedAt: startedAt,
                finishedAt: finishedAt,
                exitCode: exitCode,
                outputTail: String(localActionRunOutput.suffix(20_000))
            )
            localActionHistory.insert(record, at: 0)
            localActionHistory = Array(localActionHistory.prefix(100))
            lastLocalActionSucceeded = exitCode == 0
            localActionStatusMessage = exitCode == 0
                ? "“\(action.title)”执行成功。"
                : "“\(action.title)”执行失败，状态码：\(exitCode)"
            saveLocalActionState()
            refreshLocalActions()
        case .failure(let error):
            lastLocalActionSucceeded = false
            localActionStatusMessage = error.localizedDescription
        }
    }

    private func saveLocalActionState() {
        LocalActionPersistenceStore.save(
            favoriteIDs: localActionFavoriteIDs,
            history: localActionHistory,
            customizations: localActionCustomizations
        )
    }

    private func prependHistory(_ item: TaskHistoryItem) {
        history.insert(item, at: 0)
        if history.count > 100 {
            let removed = Array(history.dropFirst(100))
            history = Array(history.prefix(100))
            removed.forEach { TaskHistoryTranscriptStore.delete(for: $0.id) }
        }
    }

    private func updateHistory(id: UUID, succeeded: Bool) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].succeeded = succeeded
    }

    private func updateHistoryThreadID(id: UUID, threadID: String) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].threadID = threadID
    }

    private func syncHistoryTranscript(from task: BackgroundTaskSession) {
        guard let index = history.firstIndex(where: { $0.id == task.historyID }) else { return }
        history[index].threadID = task.threadID
        let transcript = TaskHistoryTranscript(
            finishedAt: task.finishedAt,
            status: task.status,
            blocks: task.blocks,
            usage: task.usage,
            exitCode: task.exitCode,
            errorMessage: task.errorMessage
        )
        history[index].transcriptAvailable = TaskHistoryTranscriptStore.save(transcript, for: task.historyID)
    }

    private func savePreferences() {
        guard !isLoading else { return }
        let preferences = PersistedPreferences(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            executionMode: executionMode,
            hotKeyPreset: hotKeyPreset,
            history: history,
            selectedAgentID: selectedAgentID,
            agentSelectionVersion: 1,
            agentCustomPaths: agentCustomPaths,
            terminalTemplate: terminalTemplate,
            chatGPTPromptPrefix: chatGPTPromptPrefix
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
