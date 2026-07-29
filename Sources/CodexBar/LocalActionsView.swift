import SwiftUI

struct LocalActionsView: View {
    @ObservedObject var state: AppState

    @State private var scope: LocalActionScope = .available
    @State private var query = ""
    @State private var pendingAction: LocalAction?
    @State private var editingAction: LocalAction?
    @State private var hoveredActionID: String?
    @FocusState private var searchFocused: Bool

    private var displayedActions: [LocalAction] {
        state.localActions(scope: scope, matching: query)
    }

    var body: some View {
        ZStack {
            LocalActionsBackdrop()

            VStack(spacing: 0) {
                header

                VStack(spacing: 14) {
                    searchBar
                    scopePicker
                    actionList
                    runResult
                }
                .padding(18)
            }
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

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.blue.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 5)

                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("项目操作")
                        .font(.title3.weight(.semibold))

                    if state.availableLocalActions.count > 0 {
                        Text("\(state.availableLocalActions.count) 可用")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.11), in: Capsule())
                    }
                }

                Text(state.selectedWorkspace.map { "\($0.name) · 从少量明确操作开始，而不是展示全部脚本" }
                     ?? "请先选择工作目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if state.isDiscoveringLocalActions {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("扫描中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                state.refreshLocalActions()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(LocalActionToolbarButtonStyle())
            .disabled(state.selectedWorkspace == nil || state.isDiscoveringLocalActions)
        }
        .padding(.horizontal, 18)
        .frame(height: 80)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.primary.opacity(0.07))
                .frame(height: 1)
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

    private var scopePicker: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(LocalActionScope.allCases) { item in
                    let selected = scope == item
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            scope = item
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                            Text("\(scopeCount(item))")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045),
                                    in: Capsule()
                                )
                        }
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.07))
                                    }
                                    .shadow(color: .black.opacity(0.09), radius: 4, y: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassSurface(cornerRadius: 12, tint: Color.primary.opacity(0.01), shadowEnabled: false)

            Spacer()

            Label("扫描到 \(state.localActions.count) 个脚本", systemImage: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.primary.opacity(0.07), lineWidth: 1)
                }
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
                icon: scope == .discovered ? "doc.badge.ellipsis" : "bolt.slash",
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(displayedActions) { action in
                        actionRow(action)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxHeight: state.localActionRunOutput.isEmpty ? .infinity : 300)
        }
    }

    private func actionRow(_ action: LocalAction) -> some View {
        let accent = actionAccent(action)
        let hovering = hoveredActionID == action.id
        let favorite = state.localActionFavoriteIDs.contains(action.id)

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

                    if !action.published {
                        LocalActionBadge(title: "未发布", systemImage: "eye.slash", color: .gray)
                    }

                    if action.isCustomized {
                        LocalActionBadge(title: "已整理", systemImage: "checkmark.seal.fill", color: .teal)
                    }

                    if action.isQuickRunnable {
                        LocalActionBadge(title: "一键执行", systemImage: "bolt.fill", color: .green)
                    } else if action.quickRunNeedsReview {
                        LocalActionBadge(title: "脚本已更新", systemImage: "arrow.triangle.2.circlepath", color: .orange)
                    }
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

            LocalActionBadge(
                title: action.risk.title,
                systemImage: action.risk.systemImage,
                color: action.risk.tintColor
            )

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
                state.toggleLocalActionFavorite(action)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
            }
            .buttonStyle(LocalActionIconButtonStyle(tint: favorite ? .orange : .gray))
            .help(favorite ? "取消收藏" : "收藏")

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

    private func emptyState(icon: String, title: String, message: String) -> some View {
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
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 18, tint: Color.accentColor.opacity(0.018), shadowEnabled: false)
    }

    private var emptyTitle: String {
        if !query.isEmpty { return "没有找到匹配的操作" }
        switch scope {
        case .available: return "当前项目还没有可用操作"
        case .favorites: return "还没有收藏操作"
        case .recent: return "还没有执行记录"
        case .discovered: return "没有发现脚本"
        }
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "可以尝试脚本名称、适用场景或问题描述。" }
        switch scope {
        case .available:
            return "在 .codexbar/actions.json 中发布操作，或到“已发现”把真正需要的脚本整理为操作。"
        case .favorites:
            return "收藏只保留真正会反复使用的操作，避免列表再次变成脚本仓库。"
        case .recent:
            return "执行过的项目操作会在这里保留，低风险操作可以从菜单栏再次运行。"
        case .discovered:
            return "CodexBar 只扫描当前项目的 Scripts、scripts、Tools 和 tools 目录。"
        }
    }

    private func scopeCount(_ item: LocalActionScope) -> Int {
        state.localActions(scope: item, matching: "").count
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

private struct GlassSurfaceModifier: ViewModifier {
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

private extension View {
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

private struct LocalActionToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.02 : 0.07), radius: 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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

private extension LocalActionScope {
    var systemImage: String {
        switch self {
        case .available: return "bolt.fill"
        case .favorites: return "star.fill"
        case .recent: return "clock.arrow.circlepath"
        case .discovered: return "doc.text.magnifyingglass"
        }
    }
}

private extension LocalActionRisk {
    var tintColor: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
