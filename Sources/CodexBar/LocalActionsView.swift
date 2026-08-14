import AppKit
import SwiftUI

/// 「操作」页在浏览模式下的轻量过滤 chips。
private enum BrowseFilter: String, CaseIterable, Identifiable {
    case all, quickRun, favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .quickRun: return "一键执行"
        case .favorites: return "收藏"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .quickRun: return "bolt.fill"
        case .favorites: return "star.fill"
        }
    }
}

struct LocalActionsView: View {
    @ObservedObject var state: AppState

    @State private var browseFilter: BrowseFilter = .all
    @State private var query = ""
    @State private var pendingAction: LocalAction?
    @State private var editingAction: LocalAction?
    @State private var hoveredActionID: String?
    @FocusState private var searchFocused: Bool

    private var displayedActions: [LocalAction] {
        let base = state.searchLocalActions(matching: query)
        switch browseFilter {
        case .all: return base
        case .quickRun: return base.filter(\.isQuickRunnable)
        case .favorites: return base.filter { state.localActionFavoriteIDs.contains($0.id) }
        }
    }

    /// manage 模式的三个分组，互斥划分避免同一脚本重复出现。
    private var reviewActions: [LocalAction] { state.reviewLocalActions }
    private var publishedActions: [LocalAction] {
        state.localActions.filter { $0.published && !$0.quickRunNeedsReview }
    }
    private var pendingActions: [LocalAction] {
        state.localActions.filter { !$0.published }
    }

    var body: some View {
        ZStack {
            LocalActionsBackdrop()

            VStack(spacing: 14) {
                modePicker
                if state.localActionsMode == .browse {
                    searchBar
                    filterChips
                    actionList
                } else {
                    manageIntro
                    manageList
                }
                runResult
            }
            .padding(18)
        }
        .alert(item: $pendingAction) { action in
            confirmationAlert(for: action)
        }
        .sheet(item: $editingAction) { action in
            LocalActionEditorSheet(
                action: action,
                existingCustomization: state.localActionCustomizations[action.id],
                onSave: { state.saveLocalActionCustomization($0) },
                onRemove: { state.removeLocalActionCustomization(for: action) }
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchFocused ? Color.accentColor : Color.secondary)

            TextField("搜索操作、用途或问题，例如“MCP 连不上”", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text("⌘F")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    searchFocused ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.08),
                    lineWidth: searchFocused ? 1.4 : 1
                )
        }
        .shadow(
            color: searchFocused ? Color.accentColor.opacity(0.16) : Color.black.opacity(0.04),
            radius: searchFocused ? 12 : 5,
            y: 3
        )
        .animation(.easeOut(duration: 0.18), value: searchFocused)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(LocalActionsMode.allCases) { mode in
                let selected = state.localActionsMode == mode
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        state.localActionsMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.regularMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.08))
                                }
                                .shadow(color: .black.opacity(0.09), radius: 4, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassSurface(cornerRadius: 11, tint: Color.primary.opacity(0.01), shadowEnabled: false)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(BrowseFilter.allCases) { item in
                let selected = browseFilter == item
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        browseFilter = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background {
                        if selected {
                            Capsule().fill(.regularMaterial)
                                .overlay(Capsule().fill(Color.accentColor.opacity(0.08)))
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .overlay {
                        Capsule().stroke(
                            selected ? Color.accentColor.opacity(0.30) : .primary.opacity(0.06),
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Label("\(state.localActions.count) 个脚本", systemImage: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionList: some View {
        if state.selectedWorkspace == nil {
            emptyState(
                icon: "folder.badge.questionmark",
                title: "尚未选择工作目录",
                message: "在左侧添加或选择一个项目后，CodexBar 会发现其中明确发布的操作。"
            )
        } else if state.isDiscoveringLocalActions && state.localActions.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在发现项目操作…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedActions.isEmpty {
            emptyState(
                icon: "bolt.slash",
                title: browseEmptyTitle,
                message: browseEmptyMessage,
                actionTitle: query.isEmpty ? "去脚本管理" : nil,
                action: query.isEmpty ? { state.localActionsMode = .manage } : nil
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(displayedActions) { action in
                        browseRow(action)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxHeight: state.localActionRunOutput.isEmpty ? .infinity : 300)
        }
    }

    private func browseRow(_ action: LocalAction) -> some View {
        let accent = actionAccent(action)
        let hovering = hoveredActionID == action.id

        return HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(accent.opacity(0.18), lineWidth: 1)
                    }

                Image(systemName: action.published ? actionIcon(action) : "doc.text.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)

                    browseBadge(action)
                }

                Text(action.primaryUsage.isEmpty ? "尚未补充适用场景" : action.primaryUsage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text(action.relativePath)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let record = latestRecord(for: action) {
                        Text("·")
                        Label(
                            record.succeeded ? relativeDate(record.finishedAt) : "上次失败",
                            systemImage: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(record.succeeded ? Color.green.opacity(0.85) : Color.red.opacity(0.9))
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button {
                requestRun(action)
            } label: {
                HStack(spacing: 6) {
                    if state.runningLocalActionID == action.id {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: action.isQuickRunnable ? "play.fill" : "checkmark.circle")
                    }
                    Text(state.runningLocalActionID == action.id
                         ? "运行中"
                         : (action.isQuickRunnable ? "运行" : "确认"))
                }
            }
            .buttonStyle(LocalActionRunButtonStyle(tint: accent))
            .disabled(state.runningLocalActionID != nil)
            .help(action.isQuickRunnable ? "立即执行" : "查看命令并确认")

            if hovering {
                rowMenu(action)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassSurface(
            cornerRadius: 14,
            tint: accent.opacity(hovering ? 0.075 : 0.025),
            shadowEnabled: hovering
        )
        .scaleEffect(hovering ? 1.003 : 1)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { isHovering in
            if isHovering {
                hoveredActionID = action.id
            } else if hoveredActionID == action.id {
                hoveredActionID = nil
            }
        }
    }

    @ViewBuilder
    private func browseBadge(_ action: LocalAction) -> some View {
        if action.quickRunNeedsReview {
            LocalActionBadge(title: "脚本已更新", systemImage: "arrow.triangle.2.circlepath", color: .orange)
        } else if !action.published {
            LocalActionBadge(title: "未发布", systemImage: "eye.slash", color: .gray)
        } else if action.isQuickRunnable {
            LocalActionBadge(title: "一键执行", systemImage: "bolt.fill", color: .green)
        }
    }

    private func rowMenu(_ action: LocalAction) -> some View {
        let favorite = state.localActionFavoriteIDs.contains(action.id)
        return Menu {
            Button {
                editingAction = action
            } label: {
                Label(action.isCustomized ? "编辑" : "整理", systemImage: action.isCustomized ? "slider.horizontal.3" : "wand.and.stars")
            }
            Button {
                state.toggleLocalActionFavorite(action)
            } label: {
                Label(favorite ? "取消收藏" : "收藏", systemImage: favorite ? "star.slash" : "star")
            }
            Divider()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: action.scriptPath)])
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(action.commandPreview, forType: .string)
            } label: {
                Label("复制命令", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("更多操作")
    }

    @ViewBuilder
    private var runResult: some View {
        if state.runningLocalActionID != nil || !state.localActionRunOutput.isEmpty || !state.localActionStatusMessage.isEmpty {
            let statusColor: Color = state.runningLocalActionID != nil
                ? .accentColor
                : (state.lastLocalActionSucceeded == false ? .red : .green)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.14))
                        if state.runningLocalActionID != nil {
                            ProgressView()
                                .controlSize(.mini)
                        } else if let succeeded = state.lastLocalActionSucceeded {
                            Image(systemName: succeeded ? "checkmark" : "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(statusColor)
                        }
                    }
                    .frame(width: 24, height: 24)

                    Text(state.localActionStatusMessage.isEmpty ? "项目操作" : state.localActionStatusMessage)
                        .font(.system(size: 12.5, weight: .semibold))

                    Spacer()

                    if state.runningLocalActionID != nil {
                        Button("停止") {
                            state.cancelRunningLocalAction()
                        }
                        .buttonStyle(LocalActionCompactButtonStyle(tint: .red))
                    }
                }

                if !state.localActionRunOutput.isEmpty {
                    ScrollView {
                        Text(state.localActionRunOutput)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 108)
                    .padding(11)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.88), Color.blue.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(0.09), lineWidth: 1)
                    }
                    .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(13)
            .glassSurface(cornerRadius: 14, tint: statusColor.opacity(0.035), shadowEnabled: false)
        }
    }

    private var manageIntro: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("自动发现 → 整理发布 → 一键执行。把高频脚本整理成带说明的操作，低风险可设为一键执行。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                state.refreshLocalActions()
            } label: {
                Label(
                    state.isDiscoveringLocalActions ? "扫描中…" : "重新扫描",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(LocalActionCompactButtonStyle(tint: .accentColor))
            .disabled(state.isDiscoveringLocalActions)
        }
        .padding(11)
        .glassSurface(cornerRadius: 12, tint: Color.primary.opacity(0.01), shadowEnabled: false)
    }

    @ViewBuilder
    private var manageList: some View {
        if state.localActions.isEmpty {
            emptyState(
                icon: "doc.text.magnifyingglass",
                title: "还没有发现脚本",
                message: "CodexBar 会扫描当前项目的 Scripts、scripts、Tools 和 tools 目录，以及 .codexbar/actions.json 中发布的脚本。",
                actionTitle: "返回操作",
                action: { state.localActionsMode = .browse }
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !reviewActions.isEmpty {
                        manageGroup(
                            title: "需复查",
                            systemImage: "arrow.triangle.2.circlepath",
                            color: .orange,
                            actions: reviewActions
                        )
                    }
                    if !publishedActions.isEmpty {
                        manageGroup(
                            title: "已发布",
                            systemImage: "bolt.fill",
                            color: .accentColor,
                            actions: publishedActions
                        )
                    }
                    if !pendingActions.isEmpty {
                        manageGroup(
                            title: "待整理",
                            systemImage: "doc.text.magnifyingglass",
                            color: .gray,
                            actions: pendingActions
                        )
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxHeight: state.localActionRunOutput.isEmpty ? .infinity : 300)
        }
    }

    private func manageGroup(title: String, systemImage: String, color: Color, actions: [LocalAction]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 4)

            ForEach(actions) { action in
                manageRow(action)
            }
        }
    }

    private func manageRow(_ action: LocalAction) -> some View {
        let accent = actionAccent(action)
        let hovering = hoveredActionID == action.id

        return HStack(spacing: 11) {
            Image(systemName: action.published ? actionIcon(action) : "doc.text.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if action.quickRunNeedsReview {
                        LocalActionBadge(title: "需复查", systemImage: "arrow.triangle.2.circlepath", color: .orange)
                    } else if !action.published {
                        LocalActionBadge(title: "待整理", systemImage: "eye.slash", color: .gray)
                    } else if action.isCustomized {
                        LocalActionBadge(title: "已整理", systemImage: "checkmark.seal.fill", color: .teal)
                    }
                }
                Text(action.relativePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                editingAction = action
            } label: {
                Label(
                    action.isCustomized ? "编辑" : "整理",
                    systemImage: action.isCustomized ? "slider.horizontal.3" : "wand.and.stars"
                )
            }
            .buttonStyle(LocalActionCompactButtonStyle(tint: action.isCustomized ? .teal : .gray))
            .help(action.isCustomized ? "编辑操作说明" : "整理为操作")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: action.scriptPath)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(LocalActionIconButtonStyle(tint: .gray))
            .help("在 Finder 中显示")

            if hovering {
                manageMenu(action)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassSurface(
            cornerRadius: 12,
            tint: accent.opacity(hovering ? 0.07 : 0.02),
            shadowEnabled: hovering
        )
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { isHovering in
            if isHovering {
                hoveredActionID = action.id
            } else if hoveredActionID == action.id {
                hoveredActionID = nil
            }
        }
    }

    private func manageMenu(_ action: LocalAction) -> some View {
        let favorite = state.localActionFavoriteIDs.contains(action.id)
        return Menu {
            Button {
                state.toggleLocalActionFavorite(action)
            } label: {
                Label(favorite ? "取消收藏" : "收藏", systemImage: favorite ? "star.slash" : "star")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(action.commandPreview, forType: .string)
            } label: {
                Label("复制命令", systemImage: "doc.on.doc")
            }
            if action.isCustomized {
                Divider()
                Button(role: .destructive) {
                    state.removeLocalActionCustomization(for: action)
                } label: {
                    Label("移除整理", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("更多操作")
    }

    private func emptyState(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
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

    private var browseEmptyTitle: String {
        if !query.isEmpty { return "没有找到匹配的操作" }
        switch browseFilter {
        case .all: return "当前项目还没有可用操作"
        case .quickRun: return "还没有可一键执行的操作"
        case .favorites: return "还没有收藏操作"
        }
    }

    private var browseEmptyMessage: String {
        if !query.isEmpty { return "可以尝试脚本名称、适用场景或问题描述。" }
        switch browseFilter {
        case .all:
            return "在 .codexbar/actions.json 中发布操作，或到「脚本管理」把真正需要的脚本整理为操作。"
        case .quickRun:
            return "在整理操作时开启「一键执行」，低风险命令就能从菜单栏直接运行。"
        case .favorites:
            return "收藏只保留真正会反复使用的操作，避免列表再次变成脚本仓库。"
        }
    }

    private func actionAccent(_ action: LocalAction) -> Color {
        if action.quickRunNeedsReview { return .orange }
        if !action.published { return .gray }
        if action.isCustomized { return .teal }
        switch action.risk {
        case .low: return .accentColor
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func actionIcon(_ action: LocalAction) -> String {
        let value = action.title.lowercased()
        if value.contains("构建") || value.contains("build") { return "hammer.fill" }
        if value.contains("安装") || value.contains("更新") || value.contains("install") { return "arrow.down.app.fill" }
        if value.contains("检查") || value.contains("check") { return "checkmark.shield.fill" }
        if value.contains("重启") || value.contains("restart") { return "power" }
        if value.contains("测试") || value.contains("test") { return "checkmark.circle.fill" }
        return "bolt.fill"
    }

    private func requestRun(_ action: LocalAction) {
        if action.isQuickRunnable {
            state.runLocalAction(action)
        } else {
            pendingAction = action
        }
    }

    private func confirmationAlert(for action: LocalAction) -> Alert {
        let usage = action.whenToUse.isEmpty
            ? action.summary
            : "适用场景：" + action.whenToUse.joined(separator: "；")
        let message = "\(usage)\n\n将执行：\n\(action.commandPreview)"
        let runButton: Alert.Button = action.risk == .high
            ? .destructive(Text("仍要执行")) { state.runLocalAction(action) }
            : .default(Text("执行")) { state.runLocalAction(action) }

        return Alert(
            title: Text(action.risk == .high ? "确认高风险操作" : "确认执行“\(action.title)”"),
            message: Text(message),
            primaryButton: runButton,
            secondaryButton: .cancel()
        )
    }

    private func latestRecord(for action: LocalAction) -> LocalActionRunRecord? {
        state.localActionHistory.first(where: { $0.actionID == action.id })
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct LocalActionEditorSheet: View {
    let action: LocalAction
    let existingCustomization: LocalActionCustomization?
    let onSave: (LocalActionCustomization) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var summary: String
    @State private var whenToUseText: String
    @State private var aliasesText: String
    @State private var risk: LocalActionRisk
    @State private var quickRun: Bool

    init(
        action: LocalAction,
        existingCustomization: LocalActionCustomization?,
        onSave: @escaping (LocalActionCustomization) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.action = action
        self.existingCustomization = existingCustomization
        self.onSave = onSave
        self.onRemove = onRemove
        _title = State(initialValue: existingCustomization?.title ?? action.title)
        _summary = State(initialValue: existingCustomization?.summary ?? action.summary)
        _whenToUseText = State(
            initialValue: (existingCustomization?.whenToUse ?? action.whenToUse).joined(separator: "\n")
        )
        _aliasesText = State(
            initialValue: (existingCustomization?.aliases ?? action.aliases).joined(separator: "，")
        )
        _risk = State(initialValue: existingCustomization?.risk ?? action.risk)
        _quickRun = State(initialValue: existingCustomization?.quickRun ?? action.quickRun)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedUsage: [String] {
        split(whenToUseText, separators: ["\n", "；", ";"])
    }

    private var normalizedAliases: [String] {
        split(aliasesText, separators: ["，", ",", "；", ";", "\n"])
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty && !normalizedUsage.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(existingCustomization == nil ? "整理为项目操作" : "编辑项目操作")
                        .font(.title3.weight(.semibold))
                    Text(action.relativePath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            if action.quickRunNeedsReview {
                Label(
                    "脚本内容已变化。一键执行已暂停，检查后保存即可重新确认。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(Color.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("名称")
                        .foregroundStyle(.secondary)
                    TextField("例如：重启本地 Controller", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow(alignment: .top) {
                    Text("作用")
                        .foregroundStyle(.secondary)
                    TextField("简要说明执行后会发生什么", text: $summary)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow(alignment: .top) {
                    Text("什么时候用")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        TextEditor(text: $whenToUseText)
                            .font(.system(size: 12))
                            .frame(height: 82)
                            .padding(5)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        Text("每行一个场景；这是搜索和推荐的主要依据。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                GridRow {
                    Text("别名")
                        .foregroundStyle(.secondary)
                    TextField("例如：恢复 harness，MCP 修复", text: $aliasesText)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("风险")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $risk) {
                        ForEach(LocalActionRisk.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                GridRow(alignment: .top) {
                    Text("执行")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("允许一键执行", isOn: $quickRun)
                            .disabled(risk != .low)
                        Text(risk == .low
                             ? "仅低风险操作可跳过确认；脚本修改后会自动暂停。"
                             : "中高风险操作每次都会显示命令并确认。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(14)
            .glassSurface(cornerRadius: 14, tint: Color.accentColor.opacity(0.018), shadowEnabled: false)

            HStack {
                if existingCustomization != nil {
                    Button("移除整理") {
                        onRemove()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    let customization = LocalActionCustomization(
                        action: action,
                        title: normalizedTitle,
                        summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                        whenToUse: normalizedUsage,
                        aliases: normalizedAliases,
                        risk: risk,
                        quickRun: quickRun
                    )
                    onSave(customization)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(LocalActionsBackdrop())
        .onChange(of: risk) { newRisk in
            if newRisk != .low {
                quickRun = false
            }
        }
    }

    private func split(_ value: String, separators: [String]) -> [String] {
        var normalized = value
        for separator in separators {
            normalized = normalized.replacingOccurrences(of: separator, with: "\n")
        }
        var seen = Set<String>()
        return normalized
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}


private struct LocalActionsBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.055),
                    Color.clear,
                    Color.cyan.opacity(0.028)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 250, height: 250)
                .blur(radius: 75)
                .offset(x: -270, y: -220)

            Circle()
                .fill(Color.blue.opacity(0.05))
                .frame(width: 230, height: 230)
                .blur(radius: 78)
                .offset(x: 310, y: 230)

            Circle()
                .fill(Color.cyan.opacity(0.055))
                .frame(width: 190, height: 190)
                .blur(radius: 70)
                .offset(x: 220, y: -210)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let shadowEnabled: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(tint)
                    }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.07),
                            Color.black.opacity(0.075)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(
                color: shadowEnabled ? Color.black.opacity(0.10) : .clear,
                radius: shadowEnabled ? 16 : 0,
                y: shadowEnabled ? 7 : 0
            )
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat,
        tint: Color = .clear,
        shadowEnabled: Bool = true
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                shadowEnabled: shadowEnabled
            )
        )
    }
}

private struct LocalActionBadge: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.105), in: Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.14), lineWidth: 1)
            }
            .fixedSize()
    }
}

private struct LocalActionCompactButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tint.opacity(configuration.isPressed ? 0.15 : 0.085), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.13), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct LocalActionIconButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.12), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

private struct LocalActionRunButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.24), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
