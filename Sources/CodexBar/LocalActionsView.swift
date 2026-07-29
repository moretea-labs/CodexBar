import SwiftUI

struct LocalActionsView: View {
    @ObservedObject var state: AppState

    @State private var scope: LocalActionScope = .available
    @State private var query = ""
    @State private var pendingAction: LocalAction?
    @State private var editingAction: LocalAction?

    private var displayedActions: [LocalAction] {
        state.localActions(scope: scope, matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)

            VStack(spacing: 14) {
                searchBar
                scopePicker
                actionList
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

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("项目操作")
                    .font(.title3.weight(.semibold))
                Text(state.selectedWorkspace.map { "\($0.name) · \(state.availableLocalActions.count) 个可用操作" }
                     ?? "请先选择工作目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.isDiscoveringLocalActions {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                state.refreshLocalActions()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(state.selectedWorkspace == nil || state.isDiscoveringLocalActions)
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索操作、用途或问题，例如“MCP 连不上”", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private var scopePicker: some View {
        HStack(spacing: 12) {
            Picker("", selection: $scope) {
                ForEach(LocalActionScope.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 430)

            Spacer()

            Text("扫描到 \(state.localActions.count) 个脚本")
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
        HStack(spacing: 12) {
            Image(systemName: action.published ? "bolt.fill" : "doc.text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(action.published ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 32)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if !action.published {
                        Text("未发布")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }

                    if action.isQuickRunnable {
                        Text("一键执行")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    } else if action.quickRunNeedsReview {
                        Text("脚本已更新")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1), in: Capsule())
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
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Label(action.risk.title, systemImage: action.risk.systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(action.risk == .high ? Color.red : Color.secondary)
                .labelStyle(.titleAndIcon)
                .fixedSize()

            Button {
                editingAction = action
            } label: {
                Image(systemName: action.isCustomized ? "slider.horizontal.3" : "wand.and.stars")
                    .foregroundStyle(action.isCustomized ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(action.isCustomized ? "编辑操作说明" : "整理为操作")

            Button {
                state.toggleLocalActionFavorite(action)
            } label: {
                Image(systemName: state.localActionFavoriteIDs.contains(action.id) ? "star.fill" : "star")
                    .foregroundStyle(state.localActionFavoriteIDs.contains(action.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(state.localActionFavoriteIDs.contains(action.id) ? "取消收藏" : "收藏")

            Button {
                requestRun(action)
            } label: {
                if state.runningLocalActionID == action.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: action.isQuickRunnable ? "play.fill" : "play")
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(state.runningLocalActionID != nil)
            .help(action.isQuickRunnable ? "立即执行" : "查看命令并确认")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(.primary.opacity(0.055), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var runResult: some View {
        if state.runningLocalActionID != nil || !state.localActionRunOutput.isEmpty || !state.localActionStatusMessage.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    if state.runningLocalActionID != nil {
                        ProgressView()
                            .controlSize(.small)
                    } else if let succeeded = state.lastLocalActionSucceeded {
                        Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(succeeded ? Color.green : Color.red)
                    }

                    Text(state.localActionStatusMessage.isEmpty ? "项目操作" : state.localActionStatusMessage)
                        .font(.system(size: 12, weight: .semibold))

                    Spacer()

                    if state.runningLocalActionID != nil {
                        Button("停止") {
                            state.cancelRunningLocalAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !state.localActionRunOutput.isEmpty {
                    ScrollView {
                        Text(state.localActionRunOutput)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 105)
                    .padding(10)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(12)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(width: 540)
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
