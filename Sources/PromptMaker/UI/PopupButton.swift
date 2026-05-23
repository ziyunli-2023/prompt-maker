import AppKit
import Carbon.HIToolbox

@MainActor
final class PopupButton: NSPanel {
    private var selectedText: String = ""
    private var anchorPoint: NSPoint = .zero
    private let historyStore: HistoryStore
    private let inputPanel: InputPanel
    private let resultPanel: ResultPreviewPanel
    private let imageView: NSImageView = {
        let view = NSImageView(frame: NSRect(x: 6, y: 6, width: 24, height: 24))
        view.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Optimize prompt")
        view.contentTintColor = .systemYellow
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }()
    private let progressIndicator: NSProgressIndicator = {
        let pi = NSProgressIndicator(frame: NSRect(x: 8, y: 8, width: 20, height: 20))
        pi.style = .spinning
        pi.controlSize = .small
        pi.isDisplayedWhenStopped = false
        return pi
    }()

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore
        self.resultPanel = ResultPreviewPanel(historyStore: historyStore)
        self.inputPanel = InputPanel(historyStore: historyStore, resultPanel: self.resultPanel)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 36, height: 36),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isReleasedWhenClosed = false

        let container = LongPressView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        container.onShortClick = { [weak self] in self?.handleShortClick() }
        container.onLongPress  = { [weak self] in self?.handleLongPress() }
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 0.5

        container.addSubview(imageView)
        container.addSubview(progressIndicator)

        self.contentView = container
    }

    override var canBecomeKey: Bool { false }

    func showAt(point: NSPoint, selectedText: String) {
        self.selectedText = selectedText
        self.anchorPoint = point
        self.setFrameOrigin(NSPoint(x: point.x - 18, y: point.y))
        self.orderFrontRegardless()
    }

    func hide() {
        self.orderOut(nil)
    }

    private func handleLongPress() {
        let text = selectedText
        let anchor = anchorPoint
        Diagnostics.log("PopupButton long-press, text length=\(text.count)")
        hide()
        inputPanel.showAt(point: anchor, selectedText: text)
    }

    private func handleShortClick() {
        guard !imageView.isHidden else { return }
        let text = selectedText
        Diagnostics.log("PopupButton short-click, text length=\(text.count)")

        imageView.isHidden = true
        progressIndicator.startAnimation(nil)

        Task { @MainActor in
            defer {
                self.imageView.isHidden = false
                self.progressIndicator.stopAnimation(nil)
                self.hide()
            }
            let service = ServiceFactory.make()
            do {
                let result = try await service.complete(input: text)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(result.optimized, forType: .string)

                self.historyStore.add(HistoryEntry(
                    id: UUID(), timestamp: Date(),
                    input: text,
                    translation: result.translation,
                    optimized: result.optimized
                ))

                try? await Task.sleep(nanoseconds: 200_000_000)
                Self.simulatePaste()
                Diagnostics.log("PopupButton: pasted optimized prompt")
            } catch {
                Diagnostics.log("PopupButton error: \(error.localizedDescription)")
            }
        }
    }

    static func simulatePaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: - LongPressView

private class LongPressView: NSView {
    var onShortClick: (() -> Void)?
    var onLongPress: (() -> Void)?
    private var pressDownAt: Date = Date()
    private var longPressTimer: Timer?
    private var longPressFired: Bool = false
    private let longPressThreshold: TimeInterval = 0.35

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        pressDownAt = Date()
        longPressFired = false
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.longPressFired = true
            self.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            self.onLongPress?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        longPressTimer?.invalidate()
        longPressTimer = nil
        if longPressFired { return }
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            onShortClick?()
        }
    }
}
