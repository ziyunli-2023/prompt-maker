import AppKit
import SwiftUI

@MainActor
final class FloatingPanel: NSPanel {
    private let promptStore: PromptStore
    private let historyStore: HistoryStore

    init(promptStore: PromptStore, historyStore: HistoryStore) {
        self.promptStore = promptStore
        self.historyStore = historyStore
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.title = "PromptMaker"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.isOpaque = true
        self.hasShadow = true
        self.backgroundColor = .windowBackgroundColor
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        let view = PromptView(
            promptStore: promptStore,
            historyStore: historyStore,
            onDismiss: { [weak self] in self?.hide() }
        )
        self.contentViewController = NSHostingController(rootView: view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        recenter()
        maybePrefillFromClipboard()
        self.makeKeyAndOrderFront(nil)
    }

    func hide() {
        self.orderOut(nil)
    }

    private func recenter() {
        guard let screen = NSScreen.main else { return }
        let frame = self.frame
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - frame.width / 2
        let y = screenRect.midY - frame.height / 2 + 80
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func maybePrefillFromClipboard() {
        let enabled = UserDefaults.standard.object(forKey: "autoFillFromClipboard") as? Bool ?? true
        guard enabled, promptStore.input.isEmpty else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 2000 else { return }
        promptStore.input = trimmed
    }
}
