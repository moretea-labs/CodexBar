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
        setupMainMenu()
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

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "CodexBar")
        appMenu.addItem(withTitle: "关于 CodexBar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 CodexBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Even though CodexBar is an accessory/panel app, a real Edit menu is
        // important: AppKit routes these nil-target actions through the first
        // responder so NSTextView, SwiftUI TextEditor and selectable output all
        // get standard macOS editing behavior.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(editItem("撤销", action: Selector(("undo:")), key: "z"))
        let redo = editItem("重做", action: Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(editItem("剪切", action: Selector(("cut:")), key: "x"))
        editMenu.addItem(editItem("复制", action: Selector(("copy:")), key: "c"))
        editMenu.addItem(editItem("粘贴", action: Selector(("paste:")), key: "v"))
        editMenu.addItem(NSMenuItem(title: "删除", action: Selector(("delete:")), keyEquivalent: ""))
        editMenu.addItem(.separator())
        editMenu.addItem(editItem("全选", action: Selector(("selectAll:")), key: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func editItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command]
        item.target = nil
        return item
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

            let actionsItem = NSMenuItem(title: "项目操作", action: #selector(showActions), keyEquivalent: "")
            actionsItem.target = self
            menu.addItem(actionsItem)

            let historyItem = NSMenuItem(title: "查看历史记录", action: #selector(showHistory), keyEquivalent: "")
            historyItem.target = self
            menu.addItem(historyItem)

            if !state.recentQuickActions.isEmpty {
                let recentMenu = NSMenu(title: "最近项目操作")
                for action in state.recentQuickActions.prefix(5) {
                    let recentItem = NSMenuItem(
                        title: action.title,
                        action: #selector(runRecentAction(_:)),
                        keyEquivalent: ""
                    )
                    recentItem.target = self
                    recentItem.representedObject = action.id
                    recentMenu.addItem(recentItem)
                }
                let recentParent = NSMenuItem(title: "最近项目操作", action: nil, keyEquivalent: "")
                recentParent.submenu = recentMenu
                menu.addItem(recentParent)
            }

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

            if let action = state.runningLocalAction {
                let runningItem = NSMenuItem(
                    title: "停止“\(action.title)”",
                    action: #selector(stopRunningAction),
                    keyEquivalent: ""
                )
                runningItem.target = self
                menu.addItem(runningItem)
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
        state.showCompactLauncher()
        panelController?.show()
    }

    @objc private func showActions() {
        state.showExpanded(.actions)
        panelController?.show()
    }

    @objc private func showHistory() {
        state.showExpanded(.history)
        panelController?.show()
    }

    @objc private func runRecentAction(_ sender: NSMenuItem) {
        guard let actionID = sender.representedObject as? String else { return }
        state.runLocalAction(id: actionID)
    }

    @objc private func stopRunningAction() {
        state.cancelRunningLocalAction()
    }

    @objc private func showTaskCenter() {
        state.showExpanded(.tasks)
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
