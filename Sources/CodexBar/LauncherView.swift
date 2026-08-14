import AppKit
import Foundation
import SwiftUI

struct LauncherView: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void
    @State private var showsSettings = false
    @State private var pendingShellCommand: ShellCommandAssessment?

    private let sidebarWidth: CGFloat = 220
    private let launcherCornerRadius: CGFloat = 22

    var body: some View {
        Group {
            if state.isExpanded {
                expandedLauncher
            } else {
                compactLauncher
            }
        }
        .frame(
            width: state.isExpanded ? 980 : 760,
            height: state.isExpanded ? 620 : 440
        )
        .clipShape(RoundedRectangle(cornerRadius: launcherCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: launcherCornerRadius, style: .continuous))
        .sheet(isPresented: $showsSettings) {
            SettingsView(state: state)
        }
        .alert(item: $pendingShellCommand) { assessment in
            commandConfirmationAlert(for: assessment)
        }
        .onExitCommand(perform: onClose)
    }

    private var expandedLauncher: some View {
        ZStack {
            LauncherVisualBackdrop()

            VStack(spacing: 0) {
                unifiedToolbar
                Rectangle()
                    .fill(.primary.opacity(0.075))
                    .frame(height: 1)
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: sidebarWidth)
                    Rectangle()
                        .fill(.primary.opacity(0.075))
                        .frame(width: 1)
                    mainContent
                }
                Rectangle()
                    .fill(.primary.opacity(0.075))
                    .frame(height: 1)
                unifiedFooter
            }
            .background(.ultraThinMaterial)
        }
    }

    private var compactLauncher: some View {
        ZStack {
            LauncherVisualBackdrop()

            VStack(spacing: 0) {
                compactHeader
                Rectangle()
                    .fill(.primary.opacity(0.07))
                    .frame(height: 1)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        compactInputCard

                        if state.runningShellCommand != nil
                            || !state.shellCommandOutput.isEmpty
                            || !state.shellCommandStatusMessage.isEmpty {
                            shellCommandResultCard(expanded: false)
                        } else {
                            compactSuggestions
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                compactFooter
                    .layoutPriority(1)
            }
            .background(.ultraThinMaterial)
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.blue.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .shadow(color: Color.accentColor.opacity(0.22), radius: 8, y: 3)

            Menu {
                ForEach(state.workspaces) { workspace in
                    Button {
                        state.selectedWorkspaceID = workspace.id
                        NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
                    } label: {
                        Label(
                            workspace.name,
                            systemImage: workspace.id == state.selectedWorkspace?.id ? "checkmark" : "folder"
                        )
                    }
                }
                Divider()
                Button("添加工作目录…", action: state.addWorkspace)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.selectedWorkspace?.name ?? "选择工作目录")
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Text(state.selectedWorkspace?.path ?? "命令和任务将在所选项目中运行")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if state.runningTaskCount > 0 {
                Button {
                    state.showExpanded(.tasks)
                } label: {
                    Label("\(state.runningTaskCount) 个任务", systemImage: "circle.dotted")
                }
                .buttonStyle(CompactGlassButtonStyle(tint: .accentColor))
            }

            Button {
                state.showExpanded(.compose)
            } label: {
                Label("展开", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(CompactGlassButtonStyle(tint: .secondary))
            .help("打开完整工作台")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var compactInputCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(inputAccent.opacity(0.12))
                    Image(systemName: state.isShellCommandInput ? "terminal.fill" : "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(inputAccent)
                }
                .frame(width: 34, height: 34)

                ZStack(alignment: .topLeading) {
                    PromptTextView(
                        text: $state.prompt,
                        onSubmit: submitLauncherInput,
                        onCancel: onClose
                    )
                    .frame(minHeight: 46, maxHeight: 64)

                    if state.prompt.isEmpty {
                        Text("输入开发任务；Shift+Enter 换行；使用 > 快速执行本地命令")
                            .font(.system(size: 15.5, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: submitLauncherInput) {
                    HStack(spacing: 6) {
                        Image(systemName: submitSystemImage)
                        Text(submitTitle)
                    }
                }
                .buttonStyle(CompactPrimaryButtonStyle(tint: inputAccent))
                .disabled(!state.canSubmitLauncherInput)
            }

            HStack(spacing: 8) {
                Label(
                    state.isShellCommandInput ? "本地命令" : "\(state.selectedAgent.title) 任务",
                    systemImage: state.isShellCommandInput ? "terminal" : "bolt.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(inputAccent)

                Text("·")
                    .foregroundStyle(.tertiary)

                if let assessment = state.shellCommandAssessment {
                    Label(assessment.risk.title, systemImage: assessment.risk.systemImage)
                        .font(.caption)
                        .foregroundStyle(commandRiskColor(assessment.risk))
                    Text(assessment.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if state.isShellCommandInput {
                    Text("在 > 后输入命令")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.taskIntent == .plan
                         ? "只读分析并生成计划"
                         : (state.executionMode == .background ? "后台执行" : "在所选终端中打开 \(state.selectedAgent.title)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !state.isShellCommandInput {
                    compactAgentPicker
                    compactIntentPicker
                }

                Spacer()

                Text(state.taskIntent == .plan && !state.isShellCommandInput ? "Enter 计划" : "Enter 执行")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(inputAccent.opacity(state.isShellCommandInput ? 0.20 : 0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.055), radius: 10, y: 4)
    }

    private var compactSuggestions: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Button {
                    state.prompt = "> "
                    NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
                } label: {
                    Label("运行本地命令", systemImage: "terminal")
                }
                .buttonStyle(CompactSuggestionButtonStyle(tint: .cyan))

                Button {
                    state.showExpanded(.actions)
                } label: {
                    Label("项目操作", systemImage: "bolt.square")
                }
                .buttonStyle(CompactSuggestionButtonStyle(tint: .blue))

                Button {
                    state.showExpanded(.compose)
                } label: {
                    Label("完整工作台", systemImage: "rectangle.split.2x1")
                }
                .buttonStyle(CompactSuggestionButtonStyle(tint: .secondary))

                Spacer()
            }

            if !state.recentShellCommands.isEmpty {
                Text("最近命令")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ForEach(Array(state.recentShellCommands.prefix(3))) { record in
                        Button {
                            state.reuseShellCommand(record.command)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(record.succeeded ? Color.green : Color.red)
                                Text(record.command)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(record.succeeded ? "成功" : "失败")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.up.left")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(.primary.opacity(0.06), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "greaterthan.square")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.cyan.opacity(0.82))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("命令模式从 > 开始")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("例如：> git status、> mvn test、> docker compose ps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private var compactFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.selectedWorkspace == nil ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(state.selectedWorkspace == nil ? "请选择工作目录" : "当前项目已就绪")
            Spacer()
            Text("> 命令")
            Text("·")
            Text("Esc 关闭")
            Text("·")
            Text(state.hotKeyPreset.title)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.primary.opacity(0.055))
                .frame(height: 1)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sidebarGroup("任务") {
                        navigationButton(.compose)
                        navigationButton(.tasks, badge: state.runningTaskCount)
                    }
                    sidebarGroup("项目") {
                        navigationButton(.actions)
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(state.workspaces) { workspace in
                                workspaceButton(workspace)
                            }
                            HStack(spacing: 8) {
                                Button(action: state.addWorkspace) {
                                    Label("添加", systemImage: "plus")
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: state.revealSelectedWorkspace) {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.plain)
                                .help("在 Finder 中显示")
                                .disabled(state.selectedWorkspace == nil)

                                Button(action: state.removeSelectedWorkspace) {
                                    Image(systemName: "minus")
                                }
                                .buttonStyle(.plain)
                                .help("移除当前目录")
                                .disabled(state.selectedWorkspace == nil)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        }
                    }
                    sidebarGroup("历史") {
                        navigationButton(.history, badge: state.history.count)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
            }

            Divider().opacity(0.45)

            Button {
                showsSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private func navigationButton(_ section: AppSection, badge: Int = 0) -> some View {
        let selected = state.navigation == section
        return Button {
            state.selectSection(section)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .frame(width: 19)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .glassSurface(
                cornerRadius: 9,
                tint: selected ? Color.accentColor.opacity(0.10) : .clear,
                shadowEnabled: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func workspaceButton(_ workspace: Workspace) -> some View {
        let selected = workspace.id == state.selectedWorkspace?.id
        return Button {
            state.selectedWorkspaceID = workspace.id
            if state.navigation == .compose {
                NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: selected ? "folder.fill" : "folder")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    Text(workspace.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .glassSurface(
                cornerRadius: 9,
                tint: selected ? Color.accentColor.opacity(0.09) : .clear,
                shadowEnabled: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch state.navigation {
        case .compose:
            composeContent
        case .actions:
            LocalActionsView(state: state)
        case .tasks:
            taskCenterContent
        case .history:
            historyContent
        }
    }

    private var composeContent: some View {
        VStack(spacing: 0) {
            promptArea
                .padding(.horizontal, 16)
                .padding(.top, 16)
            Divider()
                .opacity(0.45)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            selectedTaskPreview
        }
    }

    private var promptArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isContinuingCodexSession, let threadID = state.pendingResumeThreadID {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .foregroundStyle(Color.accentColor)
                    Text("继续 Codex 会话 · \(String(threadID.prefix(8)))…")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        state.cancelPendingResume()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("取消继续会话，改为新任务")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            ZStack(alignment: .topLeading) {
                PromptTextView(
                    text: $state.prompt,
                    onSubmit: submitLauncherInput,
                    onCancel: onClose
                )
                .frame(minHeight: 88, maxHeight: 112)

                if state.prompt.isEmpty {
                    Text("描述 Codex 任务；使用 > 快速执行当前项目中的本地命令")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Label(
                    state.shellCommandAssessment?.reason ?? (state.selectedAgentID == .chatgpt
                        ? "使用日常 Google Chrome 新建 ChatGPT 会话"
                        : (state.taskIntent == .plan ? state.taskIntent.explanation : state.executionMode.explanation)),
                    systemImage: state.isShellCommandInput ? "terminal" : "info.circle"
                )
                .font(.caption)
                .foregroundStyle(state.shellCommandAssessment.map { commandRiskColor($0.risk) } ?? Color.secondary)
                .lineLimit(1)

                Spacer()

                if state.runningTaskCount > 0 {
                    Button {
                        state.selectSection(.tasks)
                    } label: {
                        Label("\(state.runningTaskCount) 个执行中", systemImage: "circle.dotted")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                Button(action: submitLauncherInput) {
                    HStack(spacing: 7) {
                        Text(submitTitle)
                        Text("↩")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canSubmitLauncherInput)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 12, tint: .clear, shadowEnabled: false)
    }

    @ViewBuilder
    private var selectedTaskPreview: some View {
        if state.runningShellCommand != nil
            || !state.shellCommandOutput.isEmpty
            || !state.shellCommandStatusMessage.isEmpty {
            shellCommandResultCard(expanded: true)
                .padding(16)
        } else if let task = state.selectedTask {
            taskOutputPanel(task: task, compact: true)
        } else {
            emptyTaskState
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var taskCenterContent: some View {
        Group {
            if state.backgroundTasks.isEmpty {
                emptyTaskState
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(state.backgroundTasks) { task in
                                taskListRow(task)
                            }
                        }
                        .padding(10)
                    }
                    .frame(width: 275)

                    Divider().opacity(0.45)

                    if let task = state.selectedTask {
                        taskOutputPanel(task: task, compact: false)
                    } else {
                        UnifiedEmptyState(
                            icon: "square.stack",
                            title: "选择一个任务查看详情",
                            message: "从左侧列表选择一个任务，查看它的实时输出。"
                        )
                    }
                }
            }
        }
    }

    private func taskListRow(_ task: BackgroundTaskSession) -> some View {
        let selected = state.selectedTaskID == task.id || (state.selectedTaskID == nil && state.selectedTask?.id == task.id)
        return Button {
            state.selectTask(task.id)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                taskStatusIcon(task.status)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.displayPrompt)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .lineLimit(2)
                    Text("\(task.workspaceName) · \(task.createdAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .glassSurface(cornerRadius: 9, tint: selected ? Color.accentColor.opacity(0.10) : .clear, shadowEnabled: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func taskOutputPanel(task: BackgroundTaskSession, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if compact {
                    Menu {
                        ForEach(state.backgroundTasks) { candidate in
                            Button {
                                state.selectTask(candidate.id)
                            } label: {
                                Label(candidate.displayPrompt, systemImage: candidate.status.systemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            taskStatusIcon(task.status)
                            Text(task.displayPrompt)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    taskStatusIcon(task.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.displayPrompt)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        Text(task.workspacePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Text(task.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !task.blocks.isEmpty {
                    Button {
                        copyTaskOutput(task)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("复制完整任务输出")
                }

                if task.status.isRunning {
                    Button(role: .destructive) {
                        state.cancelTask(id: task.id)
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                } else {
                    Button {
                        state.removeTask(id: task.id)
                    } label: {
                        Label("移除", systemImage: "xmark")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }

            taskOutputScrollView(task: task)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func taskOutputScrollView(task: BackgroundTaskSession) -> some View {
        TaskOutputTimelineView(task: task)
            .id(task.id)
    }

    private var historyContent: some View {
        Group {
            if state.history.isEmpty {
                UnifiedEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "还没有历史任务",
                    message: "后台执行和终端交互任务都会记录在这里。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(state.history) { item in
                            historyRow(item)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func historyRow(_ item: TaskHistoryItem) -> some View {
        HStack(spacing: 10) {
            Button {
                if item.transcriptAvailable {
                    state.openHistory(item)
                } else {
                    state.useHistory(item)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.mode.systemImage)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.prompt.isEmpty ? "打开 Codex 交互会话" : item.prompt)
                            .font(.system(size: 13))
                            .lineLimit(2)
                        HStack(spacing: 5) {
                            Text("\(item.workspaceName) · \(item.agent.title) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            if item.transcriptAvailable {
                                Text("· 有输出")
                            }
                            if item.threadID != nil {
                                Text("· 可继续")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    historyStatusIcon(item.succeeded)
                    Text(item.transcriptAvailable ? "查看" : "再次使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.transcriptAvailable {
                Button {
                    state.useHistory(item)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("作为新任务再次使用")
            }

            if item.agent == .codex, item.threadID != nil {
                Button {
                    state.continueHistory(item)
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .buttonStyle(.plain)
                .help("继续这个 Codex 会话")
            }

            Button(role: .destructive) {
                state.deleteHistory(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("删除这条历史")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassSurface(cornerRadius: 10, tint: .clear, shadowEnabled: false)
    }

    private func copyTaskOutput(_ task: BackgroundTaskSession) {
        var sections: [String] = []
        sections.append("# \(task.displayPrompt)")
        sections.append("工作目录：\(task.workspacePath)")
        sections.append("Agent：\(task.agent.title) · 模式：\(task.intent.title) · 状态：\(task.status.title)")
        if let threadID = task.threadID, !threadID.isEmpty {
            sections.append("会话：\(threadID)")
        }
        for block in task.blocks {
            var lines = ["## \(block.title)"]
            if !block.body.isEmpty { lines.append(block.body) }
            if !block.detail.isEmpty { lines.append(block.detail) }
            if !block.fileChanges.isEmpty {
                lines.append(contentsOf: block.fileChanges.map { "\($0.title)：\($0.path)" })
            }
            if !block.todos.isEmpty {
                lines.append(contentsOf: block.todos.map { "\($0.completed ? "[x]" : "[ ]") \($0.text)" })
            }
            sections.append(lines.joined(separator: "\n"))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sections.joined(separator: "\n\n"), forType: .string)
    }

    private var emptyTaskState: some View {
        UnifiedEmptyState(
            icon: "rectangle.stack.badge.play",
            title: "后台任务会显示在这里",
            message: "可以连续提交多个任务，再从任务中心切换查看各自输出。",
            actionTitle: "创建新任务",
            action: { state.selectSection(.compose) }
        )
    }

    private var pinButton: some View {
        Button {
            state.isPinned.toggle()
        } label: {
            Image(systemName: state.isPinned ? "pin.fill" : "pin")
                .frame(width: 28, height: 28)
                .background(
                    state.isPinned ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .help(state.isPinned ? "取消固定；失去焦点后自动收起" : "固定窗口；切换到其他应用时保持显示")
    }

    private var unifiedToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.blue.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .shadow(color: Color.accentColor.opacity(0.20), radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("CodexBar · \(state.navigation.title)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(state.selectedWorkspace?.name ?? "未选择目录") · \(state.selectedWorkspace?.path ?? "请先添加工作目录")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            agentPicker

            toolbarSectionActions

            collapseButton

            pinButton
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var collapseButton: some View {
        Button {
            state.collapseLauncher()
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("收起为快捷启动栏")
    }

    private var agentPicker: some View {
        Menu {
            ForEach(AgentKind.allCases) { agent in
                Button {
                    state.selectedAgentID = agent
                } label: {
                    Label(
                        agent.title,
                        systemImage: agent == state.selectedAgent ? "checkmark" : agent.systemImage
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: state.selectedAgent.systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(state.selectedAgent.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("切换执行 Agent")
    }

    private var compactIntentPicker: some View {
        Menu {
            ForEach(AgentTaskIntent.allCases) { intent in
                Button {
                    state.taskIntent = intent
                } label: {
                    Label(intent.title, systemImage: intent == state.taskIntent ? "checkmark" : (intent == .plan ? "list.bullet.rectangle" : "bolt.fill"))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.taskIntent == .plan ? "list.bullet.rectangle" : "bolt.fill")
                    .font(.caption)
                Text(state.taskIntent.title)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(state.taskIntent.explanation)
    }

    private var compactAgentPicker: some View {
        Menu {
            ForEach(AgentKind.allCases) { agent in
                Button {
                    state.selectedAgentID = agent
                } label: {
                    Label(
                        agent.title,
                        systemImage: agent == state.selectedAgent ? "checkmark" : agent.systemImage
                    )
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.selectedAgent.systemImage)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(state.selectedAgent.title)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var toolbarSectionActions: some View {
        switch state.navigation {
        case .compose:
            Picker("", selection: $state.taskIntent) {
                ForEach(AgentTaskIntent.allCases) { intent in
                    Text(intent.shortTitle).tag(intent)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 118)
            .help(state.taskIntent.explanation)

            Picker("", selection: $state.executionMode) {
                ForEach(ExecutionMode.allCases) { mode in
                    Label(mode.shortTitle, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .disabled(state.taskIntent == .plan || state.isContinuingCodexSession)
            .help(state.isContinuingCodexSession ? "继续历史 Codex 会话当前仅支持后台模式" : state.executionMode.explanation)
        case .actions:
            if state.isDiscoveringLocalActions {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
            Button {
                state.localActionsMode = state.localActionsMode == .browse ? .manage : .browse
            } label: {
                Label(
                    state.localActionsMode == .browse ? "管理脚本" : "返回操作",
                    systemImage: state.localActionsMode == .browse ? "slider.horizontal.3" : "bolt.fill"
                )
            }
            .buttonStyle(.plain)
            .font(.caption)
            .help("在操作列表与脚本管理之间切换")

            Button {
                state.refreshLocalActions()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .disabled(state.selectedWorkspace == nil)
            .help("重新扫描项目操作")
        case .tasks:
            if state.runningTaskCount > 0 {
                Label("\(state.runningTaskCount) 个执行中", systemImage: "circle.dotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if state.completedTaskCount > 0 {
                Button("清理已完成") {
                    state.clearCompletedTasks()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        case .history:
            if !state.history.isEmpty {
                Button("清空历史", role: .destructive) {
                    state.clearHistory()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
    }

    private func sidebarGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            content()
        }
    }

    private func taskStatusIcon(_ status: BackgroundTaskStatus) -> some View {
        Group {
            if status == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.systemImage)
                    .foregroundStyle(statusColor(status))
            }
        }
    }

    private func historyStatusIcon(_ succeeded: Bool?) -> some View {
        Group {
            if let succeeded {
                Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(succeeded ? Color.green : Color.red)
            } else {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusColor(_ status: BackgroundTaskStatus) -> Color {
        switch status {
        case .running: return .secondary
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private func outputPlaceholder(for task: BackgroundTaskSession) -> String {
        switch task.status {
        case .running: return "等待 \(task.agent.title) 输出…"
        case .succeeded: return "任务已完成，但没有产生文本输出。"
        case .failed: return "任务执行失败。"
        case .cancelled: return "任务已停止。"
        }
    }

    private var inputAccent: Color {
        state.isShellCommandInput ? .cyan : .accentColor
    }

    private var submitTitle: String {
        if let assessment = state.shellCommandAssessment {
            switch assessment.risk {
            case .low: return "执行命令"
            case .confirm: return "确认命令"
            case .terminalOnly: return "打开 Terminal"
            }
        }
        if state.selectedAgentID == .chatgpt { return "发送" }
        if state.taskIntent == .plan { return "生成计划" }
        return state.executionMode == .background ? "执行任务" : "打开 \(state.selectedAgent.title)"
    }

    private var submitSystemImage: String {
        if let assessment = state.shellCommandAssessment {
            return assessment.risk == .terminalOnly ? "terminal.fill" : "play.fill"
        }
        if state.selectedAgentID == .chatgpt { return "paperplane.fill" }
        if state.taskIntent == .plan { return "list.bullet.rectangle" }
        return state.executionMode == .background ? "bolt.fill" : "terminal.fill"
    }

    private func submitLauncherInput() {
        guard state.canSubmitLauncherInput else { return }
        guard let command = state.parsedShellCommand else {
            state.runCurrentTask()
            return
        }
        guard !command.isEmpty else { return }
        requestShellCommand(command)
    }

    private func requestShellCommand(_ command: String) {
        let assessment = ShellCommandPolicy.assess(command)
        switch assessment.risk {
        case .low:
            state.runShellCommand(command)
        case .confirm, .terminalOnly:
            pendingShellCommand = assessment
        }
    }

    private func commandConfirmationAlert(for assessment: ShellCommandAssessment) -> Alert {
        let directory = state.selectedWorkspace?.path ?? "未选择工作目录"
        let message = "\(assessment.reason)\n\n执行目录：\n\(directory)\n\n命令：\n\(assessment.command)"
        if assessment.risk == .terminalOnly {
            return Alert(
                title: Text("此命令仅允许在 Terminal 中执行"),
                message: Text(message),
                primaryButton: .default(Text("打开 Terminal")) {
                    state.openShellCommandInTerminal(assessment.command)
                },
                secondaryButton: .cancel()
            )
        }
        return Alert(
            title: Text("确认执行本地命令"),
            message: Text(message),
            primaryButton: .default(Text("执行")) {
                state.runShellCommand(assessment.command)
            },
            secondaryButton: .cancel()
        )
    }

    private func commandRiskColor(_ risk: ShellCommandRisk) -> Color {
        switch risk {
        case .low: return .green
        case .confirm: return .orange
        case .terminalOnly: return .red
        }
    }

    @ViewBuilder
    private func shellCommandResultCard(expanded: Bool) -> some View {
        let statusColor: Color = state.runningShellCommand != nil
            ? .cyan
            : (state.lastShellCommandSucceeded == false ? .red : .green)
        let command = state.runningShellCommand ?? state.lastShellCommand

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.13))
                    if state.runningShellCommand != nil {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: state.lastShellCommandSucceeded == false ? "xmark" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.shellCommandStatusMessage.isEmpty ? "本地命令" : state.shellCommandStatusMessage)
                        .font(.system(size: 12.5, weight: .semibold))
                    if let command {
                        Text(command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if state.runningShellCommand != nil {
                    Button(action: state.cancelRunningShellCommand) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(CompactCommandActionButtonStyle(tint: .red))
                    .help("停止命令")
                } else if let command {
                    Button {
                        requestShellCommand(command)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(CompactCommandActionButtonStyle(tint: .secondary))
                    .help("重新执行")

                    Button {
                        state.openShellCommandInTerminal(command)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .buttonStyle(CompactCommandActionButtonStyle(tint: .secondary))
                    .help("在 Terminal 中运行")
                }

                if !state.shellCommandOutput.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.shellCommandOutput, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(CompactCommandActionButtonStyle(tint: .secondary))
                    .help("复制输出")
                }

                if state.runningShellCommand == nil {
                    Button {
                        state.clearShellCommandResult()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(CompactCommandActionButtonStyle(tint: .secondary))
                    .help("关闭结果")
                }
            }

            if !state.shellCommandOutput.isEmpty {
                ScrollView {
                    Text(state.shellCommandOutput)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: expanded ? 190 : 98)
                .padding(10)
                .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(expanded ? 12 : 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusColor.opacity(0.13), lineWidth: 1)
        }
    }

    private var unifiedFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .frame(width: 7, height: 7)
                .foregroundStyle(state.selectedAgentID == .chatgpt || state.effectiveAgentPath(for: state.selectedAgentID) != nil ? .green : .red)

            if state.isDetectingAgents {
                Text("正在检测 Agent…")
            } else if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .lineLimit(1)
            } else if state.runningTaskCount > 0 {
                Text("\(state.runningTaskCount) 个后台任务执行中")
            } else if state.selectedAgentID == .chatgpt {
                Text("ChatGPT 已就绪 · Google Chrome")
            } else if let path = state.effectiveAgentPath(for: state.selectedAgentID) {
                Text("\(state.selectedAgent.title) 已就绪 · \(path)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("未检测到 \(state.selectedAgent.title) CLI")
            }

            Spacer()

            Text(state.isPinned ? "已固定" : "弹窗模式")
            Text("·")
            Text("Esc 关闭")
            Text("·")
            Text(state.hotKeyPreset.title)
        }
        .font(.caption)
        .foregroundStyle(state.lastRunSucceeded == false ? Color.red : Color.secondary)
        .padding(.horizontal, 16)
        .frame(height: 36)
    }
}

private struct TaskOutputTimelineView: View {
    let task: BackgroundTaskSession

    @State private var isBottomVisible = true
    @State private var hasPositionedInitially = false

    private var bottomID: String { "task-output-bottom-\(task.id.uuidString)" }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if task.blocks.isEmpty {
                                VStack(spacing: 9) {
                                    if task.status.isRunning {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(outputPlaceholder)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                            } else {
                                ForEach(task.blocks) { block in
                                    CodexOutputBlockView(block: block)
                                }
                            }

                            if let errorMessage = task.errorMessage,
                               !errorMessage.isEmpty,
                               !task.status.isRunning,
                               !task.blocks.contains(where: { $0.kind == .error && $0.body == errorMessage }) {
                                CodexOutputBlockView(
                                    block: CodexOutputBlock(
                                        kind: .error,
                                        title: "任务错误",
                                        body: errorMessage,
                                        status: .failed
                                    )
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomID)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: TaskOutputBottomPreferenceKey.self,
                                            value: geometry.frame(in: .named("task-output-scroll")).maxY
                                        )
                                    }
                                )
                        }
                        .padding(12)
                    }
                    .coordinateSpace(name: "task-output-scroll")
                    .onPreferenceChange(TaskOutputBottomPreferenceKey.self) { bottomY in
                        guard hasPositionedInitially else { return }
                        isBottomVisible = bottomY <= viewport.size.height + 28
                    }
                    .onAppear {
                        scrollToBottom(proxy, animated: false)
                        DispatchQueue.main.async {
                            hasPositionedInitially = true
                        }
                    }
                    .onChange(of: task.outputRevision) { _ in
                        if isBottomVisible || !hasPositionedInitially {
                            scrollToBottom(proxy, animated: true)
                        }
                    }

                    if !isBottomVisible {
                        Button {
                            scrollToBottom(proxy, animated: true)
                            isBottomVisible = true
                        } label: {
                            Label("回到底部", systemImage: "arrow.down.to.line.compact")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.bordered)
                        .background(.regularMaterial, in: Capsule())
                        .clipShape(Capsule())
                        .padding(14)
                    }
                }
            }
        }
        .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var outputPlaceholder: String {
        switch task.status {
        case .running: return "Codex 正在启动并分析任务…"
        case .succeeded: return "任务已完成，但没有返回可显示的内容。"
        case .failed: return "任务执行失败。"
        case .cancelled: return "任务已停止。"
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.14), action)
            } else {
                action()
            }
        }
    }
}

private struct TaskOutputBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CodexOutputBlockView: View {
    let block: CodexOutputBlock
    @State private var isExpanded: Bool

    init(block: CodexOutputBlock) {
        self.block = block
        _isExpanded = State(initialValue: block.kind != .reasoning)
    }

    var body: some View {
        switch block.kind {
        case .lifecycle:
            lifecycleRow
        case .agentMessage:
            agentMessageCard
        case .reasoning:
            reasoningCard
        case .command:
            commandCard
        case .fileChange:
            fileChangeCard
        case .todoList:
            todoCard
        case .webSearch:
            standardCard {
                selectableText(block.body)
            }
        case .mcpTool:
            mcpCard
        case .error:
            errorCard
        case .diagnostic, .unknown:
            diagnosticCard
        }
    }

    private var lifecycleRow: some View {
        HStack(spacing: 8) {
            blockIcon
            Text(block.title)
                .font(.caption.weight(.medium))
            if !block.detail.isEmpty {
                Text(block.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusView
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var agentMessageCard: some View {
        HStack(alignment: .top, spacing: 10) {
            blockIcon
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text(block.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                MarkdownOutputView(text: block.body)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .overlay(cardBorder)
    }

    private var reasoningCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    blockIcon
                    Text(block.title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    statusView
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, !block.body.isEmpty {
                Divider().padding(.vertical, 9)
                MarkdownOutputView(text: block.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(cardBorder)
    }

    private var commandCard: some View {
        standardCard {
            VStack(alignment: .leading, spacing: 8) {
                if !block.body.isEmpty {
                    Text(block.body)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
                if !block.detail.isEmpty {
                    Text(block.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                if let exitCode = block.exitCode {
                    Text("退出码：\(exitCode)")
                        .font(.caption2)
                        .foregroundStyle(exitCode == 0 ? Color.secondary : Color.red)
                }
            }
        }
    }

    private var fileChangeCard: some View {
        standardCard {
            VStack(alignment: .leading, spacing: 7) {
                if block.fileChanges.isEmpty {
                    Text("Codex 正在准备文件变更…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(block.fileChanges.enumerated()), id: \.offset) { _, change in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: change.systemImage)
                                .foregroundStyle(change.kind == "delete" ? Color.red : Color.secondary)
                            Text(change.title)
                                .font(.caption.weight(.medium))
                                .frame(width: 32, alignment: .leading)
                            Text(change.path)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    private var todoCard: some View {
        standardCard {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(block.todos.enumerated()), id: \.offset) { _, todo in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(todo.completed ? Color.green : Color.secondary)
                        Text(todo.text)
                            .font(.system(size: 12))
                            .strikethrough(todo.completed, color: .secondary)
                            .foregroundStyle(todo.completed ? Color.secondary : Color.primary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var mcpCard: some View {
        standardCard {
            VStack(alignment: .leading, spacing: 8) {
                if !block.body.isEmpty {
                    outputSection(title: "参数", text: block.body)
                }
                if !block.detail.isEmpty {
                    outputSection(title: block.status == .failed ? "错误" : "结果", text: block.detail)
                }
            }
        }
    }

    private var errorCard: some View {
        standardCard {
            selectableText(block.body)
                .foregroundStyle(.red)
        }
        .background(.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }

    private var diagnosticCard: some View {
        standardCard {
            selectableText(block.body)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func standardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                blockIcon
                Text(block.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                statusView
            }
            content()
        }
        .padding(11)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(cardBorder)
    }

    private var blockIcon: some View {
        Image(systemName: block.kind.systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var statusView: some View {
        if let status = block.status {
            HStack(spacing: 4) {
                if status == .inProgress {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: status.systemImage)
                }
                Text(status.title)
            }
            .font(.caption2)
            .foregroundStyle(status == .failed ? Color.red : Color.secondary)
        }
    }

    private var iconColor: Color {
        switch block.kind {
        case .agentMessage: return Color.accentColor
        case .reasoning: return Color.purple
        case .command: return Color.secondary
        case .fileChange: return Color.orange
        case .mcpTool: return Color.blue
        case .webSearch: return Color.blue
        case .todoList: return Color.green
        case .lifecycle: return Color.secondary
        case .error: return Color.red
        case .diagnostic, .unknown: return Color.secondary
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 9)
            .stroke(.primary.opacity(0.07), lineWidth: 1)
    }

    private func selectableText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12))
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct MarkdownOutputView: View {
    let text: String

    private var segments: [MarkdownSegment] {
        MarkdownSegment.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .markdown:
                    Text(markdownAttributedString(segment.content))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language):
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(language.isEmpty ? "代码" : language)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(segment.content, forType: .string)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.plain)
                            .help("复制代码")
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)

                        Divider().opacity(0.45)

                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(segment.content)
                                .font(.system(size: 11.5, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(9)
                        }
                    }
                    .background(.black.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.primary.opacity(0.07), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func markdownAttributedString(_ value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
    }
}

private struct MarkdownSegment: Identifiable {
    enum Kind {
        case markdown
        case code(language: String)
    }

    let id = UUID()
    let kind: Kind
    let content: String

    static func parse(_ value: String) -> [MarkdownSegment] {
        let lines = value.components(separatedBy: "\n")
        var result: [MarkdownSegment] = []
        var buffer: [String] = []
        var isInsideCode = false
        var language = ""

        func flushMarkdown() {
            guard !buffer.isEmpty else { return }
            result.append(MarkdownSegment(kind: .markdown, content: buffer.joined(separator: "\n")))
            buffer.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            result.append(MarkdownSegment(kind: .code(language: language), content: buffer.joined(separator: "\n")))
            buffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.hasPrefix("```") {
                if isInsideCode {
                    flushCode()
                    isInsideCode = false
                    language = ""
                } else {
                    flushMarkdown()
                    isInsideCode = true
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            } else {
                buffer.append(line)
            }
        }

        if isInsideCode {
            flushCode()
        } else {
            flushMarkdown()
        }

        if result.isEmpty {
            result.append(MarkdownSegment(kind: .markdown, content: value))
        }
        return result
    }
}


private struct LauncherVisualBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.075),
                    Color.clear,
                    Color.cyan.opacity(0.032)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.13))
                .frame(width: 320, height: 320)
                .blur(radius: 95)
                .offset(x: -360, y: -270)

            Circle()
                .fill(Color.blue.opacity(0.06))
                .frame(width: 280, height: 280)
                .blur(radius: 100)
                .offset(x: 390, y: 270)

            Circle()
                .fill(Color.cyan.opacity(0.065))
                .frame(width: 230, height: 230)
                .blur(radius: 90)
                .offset(x: 270, y: -280)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}


private struct CompactGlassButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.13), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct CompactPrimaryButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 31)
            .background(
                LinearGradient(
                    colors: isEnabled
                        ? [tint.opacity(0.94), tint.opacity(0.76)]
                        : [Color.primary.opacity(0.055), Color.primary.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isEnabled ? Color.white.opacity(0.12) : Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(
                color: isEnabled ? tint.opacity(configuration.isPressed ? 0.05 : 0.13) : .clear,
                radius: 5,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.82)
    }
}

private struct CompactCommandActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(
                tint.opacity(configuration.isPressed ? 0.12 : 0.055),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct CompactSuggestionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .frame(height: 31)
            .background(tint.opacity(configuration.isPressed ? 0.14 : 0.075), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(tint.opacity(0.12), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Shared empty-state used across workspace sections so the panel reads as one
/// surface rather than four hand-rolled placeholders.
struct UnifiedEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.15), Color.cyan.opacity(0.055)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
            .frame(width: 54, height: 54)

            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 18, tint: Color.accentColor.opacity(0.018), shadowEnabled: false)
    }
}
