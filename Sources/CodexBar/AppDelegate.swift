import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var panelController: LauncherPanelController?
    private var globalHotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = LauncherPanelController(state: state)
        setupStatusItem()
        registerHotKey(state.hotKeyPreset)

        state.$hotKeyPreset
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] preset in
                self?.registerHotKey(preset)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.cancelAllRunningTasks()
    }

    private func registerHotKey(_ preset: HotKeyPreset) {
        globalHotKey = nil
        do {
            globalHotKey = try GlobalHotKey(preset: preset) { [weak self] in
                self?.panelController?.toggle()
            }
            if state.statusMessage.contains("快捷键注册失败") {
                state.statusMessage = ""
            }
        } catch {
            state.statusMessage = error.localizedDescription
            panelController?.show()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "CodexBar")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            panelController?.toggle()
            return
        }

        if event.type == .rightMouseUp {
            let menu = NSMenu()

            let openItem = NSMenuItem(title: "打开 CodexBar", action: #selector(showPanel), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)

            let historyItem = NSMenuItem(title: "查看历史记录", action: #selector(showHistory), keyEquivalent: "")
            historyItem.target = self
            menu.addItem(historyItem)

            let pinItem = NSMenuItem(title: "固定窗口", action: #selector(togglePinned), keyEquivalent: "")
            pinItem.target = self
            pinItem.state = state.isPinned ? .on : .off
            menu.addItem(pinItem)

            if state.runningTaskCount > 0 {
                let taskItem = NSMenuItem(
                    title: "任务中心（\(state.runningTaskCount) 个执行中）",
                    action: #selector(showTaskCenter),
                    keyEquivalent: ""
                )
                taskItem.target = self
                menu.addItem(taskItem)
            }

            menu.addItem(.separator())
            let quitItem = NSMenuItem(title: "退出 CodexBar", action: #selector(quitApp), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)

            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            panelController?.toggle()
        }
    }

    @objc private func showPanel() {
        state.navigation = .compose
        panelController?.show()
    }

    @objc private func showHistory() {
        state.navigation = .history
        panelController?.show()
    }

    @objc private func showTaskCenter() {
        state.navigation = .tasks
        panelController?.show()
    }

    @objc private func togglePinned() {
        state.isPinned.toggle()
        panelController?.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
