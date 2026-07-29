import AppKit
import Combine
import SwiftUI

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherPanelController: NSWindowController, NSWindowDelegate {
    private let compactSize = NSSize(width: 760, height: 420)
    private let expandedSize = NSSize(width: 980, height: 620)
    private let state: AppState
    private var hasPositionedWindow = false
    private var cancellables = Set<AnyCancellable>()

    private var targetSize: NSSize {
        state.isExpanded ? expandedSize : compactSize
    }

    init(state: AppState) {
        self.state = state
        let panel = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow

        super.init(window: panel)
        panel.delegate = self

        let rootView = LauncherView(
            state: state,
            onClose: { [weak panel] in panel?.orderOut(nil) }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        effectView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
        panel.contentView = effectView

        state.$isExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resizeWindowForCurrentMode()
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            hide()
        } else {
            state.showCompactLauncher()
            show()
        }
    }

    func show() {
        guard let window else { return }
        resizeWindowForCurrentMode(animated: false)
        if !state.isPinned || !hasPositionedWindow {
            position(window)
            hasPositionedWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if state.navigation == .compose {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .codexBarFocusPrompt, object: nil)
            }
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              panel.attachedSheet == nil,
              !state.isPresentingSystemPanel,
              !state.isPinned else { return }
        panel.orderOut(nil)
    }

    private func resizeWindowForCurrentMode(animated: Bool? = nil) {
        guard let window else { return }
        let size = targetSize
        let frame = window.frame
        guard abs(frame.width - size.width) > 0.5 || abs(frame.height - size.height) > 0.5 else { return }

        let newFrame = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(newFrame, display: true, animate: animated ?? window.isVisible)
    }

    private func position(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let size = targetSize
        if window.frame.size != size {
            window.setContentSize(size)
        }
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - min(90, visibleFrame.height * 0.12)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
