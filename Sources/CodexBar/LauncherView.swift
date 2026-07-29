import AppKit
import Foundation
import SwiftUI

struct LauncherView: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void
    @State private var showsSettings = false

    private let sidebarWidth: CGFloat = 220

    var body: some View {
        ZStack {
            LauncherVisualBackdrop()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                Rectangle()
                    .fill(.primary.opacity(0.075))
                    .frame(width: 1)
                mainContent
            }
            .background(.ultraThinMaterial)
        }
        .frame(width: 980, height: 620)
        .sheet(isPresented: $showsSettings) {
            SettingsView(state: state)
        }
        .onExitCommand(perform: onClose)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.indigo.opacity(0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CodexBar")
                        .font(.headline)
                    Text("快捷任务入口")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            VStack(spacing: 4) {
                navigationButton(.compose)
                navigationButton(.actions)
                navigationButton(.tasks, badge: state.runningTaskCount)
                navigationButton(.history, badge: state.history.count)
            }
            .padding(.horizontal, 8)

            Divider().opacity(0.45)

            Text("工作目录")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(state.workspaces) { workspace in
                        workspaceButton(workspace)
                    }
                }
                .padding(.horizontal, 8)
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
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            Divider().opacity(0.45)

            Button {
                showsSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
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
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.095) : Color.clear)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 1)
            }
            .shadow(color: selected ? Color.accentColor.opacity(0.10) : .clear, radius: 7, y: 3)
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
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.085) : Color.clear)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.16) : Color.clear, lineWidth: 1)
            }
            .shadow(color: selected ? Color.accentColor.opacity(0.08) : .clear, radius: 6, y: 2)
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
            composeHeader
            Divider().opacity(0.45)
            promptArea
            Divider().opacity(0.45)
            selectedTaskPreview
            Divider().opacity(0.45)
            footer
        }
    }

    private var composeHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.selectedWorkspace?.name ?? "未选择目录")
                    .font(.headline)
                Text(state.selectedWorkspace?.path ?? "请先添加工作目录")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Picker("", selection: $state.executionMode) {
                ForEach(ExecutionMode.allCases) { mode in
                    Label(mode.shortTitle, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)

            pinButton
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }

    private var promptArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                PromptTextView(
                    text: $state.prompt,
                    onSubmit: state.runCurrentTask,
                    onCancel: onClose
                )
                .frame(minHeight: 88, maxHeight: 112)

                if state.prompt.isEmpty {
                    Text(state.executionMode == .background
                         ? "描述任务；提交后可立即继续输入并启动另一个任务"
                         : "可输入初始任务；留空则直接打开 Codex 交互会话")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Label(state.executionMode.explanation, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                Button(action: state.runCurrentTask) {
                    HStack(spacing: 7) {
                        Text(state.executionMode == .background ? "执行任务" : "打开 Codex")
                        Text("↩")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canRun)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var selectedTaskPreview: some View {
        if let task = state.selectedTask {
            taskOutputPanel(task: task, compact: true)
        } else {
            emptyTaskState
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var taskCenterContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("任务中心")
                        .font(.headline)
                    Text(state.runningTaskCount == 0
                         ? "当前没有执行中的后台任务"
                         : "\(state.runningTaskCount) 个任务执行中，可随时切换查看")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if state.completedTaskCount > 0 {
                    Button("清理已完成") {
                        state.clearCompletedTasks()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                pinButton
            }
            .padding(.horizontal, 18)
            .frame(height: 64)

            Divider().opacity(0.45)

            if state.backgroundTasks.isEmpty {
                emptyTaskState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .background(.black.opacity(0.025))

                    Divider().opacity(0.45)

                    if let task = state.selectedTask {
                        taskOutputPanel(task: task, compact: false)
                    } else {
                        Text("选择一个任务查看详情")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            Divider().opacity(0.45)
            footer
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
            .background(
                selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 9)
            )
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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("历史记录")
                        .font(.headline)
                    Text("保留最近 100 条任务；点击可重新载入任务和目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !state.history.isEmpty {
                    Button("清空历史", role: .destructive) {
                        state.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                pinButton
            }
            .padding(.horizontal, 18)
            .frame(height: 64)

            Divider().opacity(0.45)

            if state.history.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("还没有历史任务")
                        .font(.headline)
                    Text("后台执行和终端交互任务都会记录在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Divider().opacity(0.45)
            footer
        }
    }

    private func historyRow(_ item: TaskHistoryItem) -> some View {
        HStack(spacing: 10) {
            Button {
                state.useHistory(item)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.mode.systemImage)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.prompt.isEmpty ? "打开 Codex 交互会话" : item.prompt)
                            .font(.system(size: 13))
                            .lineLimit(2)
                        Text("\(item.workspaceName) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    historyStatusIcon(item.succeeded)
                    Text("再次使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var emptyTaskState: some View {
        VStack(spacing: 9) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("后台任务会显示在这里")
                .font(.headline)
            Text("可以连续提交多个任务，再从任务中心切换查看各自输出。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("创建新任务") {
                state.selectSection(.compose)
            }
            .buttonStyle(.bordered)
        }
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
        case .running: return "等待 Codex 输出…"
        case .succeeded: return "任务已完成，但没有产生文本输出。"
        case .failed: return "任务执行失败。"
        case .cancelled: return "任务已停止。"
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .frame(width: 7, height: 7)
                .foregroundStyle(state.effectiveCodexPath == nil ? .red : .green)

            if state.isDetectingCodex {
                Text("正在检测 Codex…")
            } else if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .lineLimit(1)
            } else if state.runningTaskCount > 0 {
                Text("\(state.runningTaskCount) 个后台任务执行中")
            } else {
                Text(state.effectiveCodexPath == nil ? "未检测到 Codex CLI" : "Codex 已就绪")
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
        .padding(.horizontal, 18)
        .frame(height: 40)
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
                    Color.indigo.opacity(0.045)
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
                .fill(Color.purple.opacity(0.09))
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
