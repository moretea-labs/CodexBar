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

            GroupBox("Codex CLI") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("自动检测，或指定 codex 可执行文件", text: $state.customCodexPath)
                            .textFieldStyle(.roundedBorder)
                        Button("选择…") { state.chooseCodexExecutable() }
                        Button("重新检测") { state.detectCodex() }
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundStyle(state.effectiveCodexPath == nil ? .red : .green)
                        Text(state.effectiveCodexPath ?? "未检测到 Codex")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
                    Text("应用每次启动默认进入后台模式。后台模式使用 workspace-write 沙箱；需要连续交互时可临时切换到终端。")
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
        .frame(width: 620, height: 500)
    }
}
