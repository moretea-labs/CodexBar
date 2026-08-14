import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("CodexBar 设置")
                    .font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            GroupBox("全局快捷键") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("唤起浮层", selection: $state.hotKeyPreset) {
                        ForEach(HotKeyPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Text("修改后立即重新注册。若失败，请换一个未被系统或其他应用占用的组合。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Agent") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("默认 Agent", selection: $state.selectedAgentID) {
                        ForEach(AgentKind.allCases) { agent in
                            Label(agent.title, systemImage: agent.systemImage).tag(agent)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(AgentKind.localAgents) { agent in
                        agentRow(agent)
                    }
                }
                .padding(8)
            }

            GroupBox("ChatGPT") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Prompt 前缀，例如 @repo-harness6", text: $state.chatGPTPromptPrefix)
                        .textFieldStyle(.roundedBorder)
                    Text("从输入框发送到 ChatGPT 时，会把这里的内容放在原始指令之前，并使用你日常的 Google Chrome 打开 chatgpt.com 新会话。留空即可不添加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("终端模板") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("预设：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(TerminalTemplate.presets, id: \.name) { preset in
                            Button(preset.name) {
                                state.terminalTemplate = preset.source
                            }
                        }
                        .controlSize(.small)
                    }

                    TextEditor(text: $state.terminalTemplate)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        }

                    Text("占位符：{command}（要执行的命令）、{cwd}（工作目录）。模板使用 AppleScript，可打开任意终端应用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("执行策略") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("当前方式", selection: $state.executionMode) {
                        ForEach(ExecutionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text("应用每次启动默认进入后台模式。后台模式使用所选 Agent 且不请求审批；需要连续交互时可临时切换到终端。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("窗口行为") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("固定窗口", isOn: $state.isPinned)
                    Text("未固定时与 Spotlight 类似，点击窗口外自动收起；固定后切换到其他应用仍保持显示。重启后恢复默认弹窗模式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 660, height: 710)
    }

    private func agentRow(_ agent: AgentKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(state.effectiveAgentPath(for: agent) == nil ? .red : .green)
                Text(agent.title)
                    .font(.caption.weight(.semibold))
                    .frame(width: 44, alignment: .leading)
                TextField("自动检测，或指定 \(agent.commandName) 可执行文件", text: agentPathBinding(agent))
                    .textFieldStyle(.roundedBorder)
                Button("选择…") { state.chooseExecutable(for: agent) }
                Button("重新检测") { state.detectAgent(agent) }
            }
            Text(state.effectiveAgentPath(for: agent) ?? "未检测到 \(agent.title)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 58)
        }
    }

    private func agentPathBinding(_ agent: AgentKind) -> Binding<String> {
        Binding(
            get: { state.agentCustomPaths[agent.rawValue] ?? "" },
            set: { state.agentCustomPaths[agent.rawValue] = $0 }
        )
    }
}
