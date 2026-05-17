import AppKit
import Carbon.HIToolbox

@MainActor
final class PopupButton: NSPanel {
    private var selectedText: String = ""
    private let historyStore: HistoryStore
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

        let container = ClickableView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        container.onMouseDown = { [weak self] in self?.handleClick() }
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
        self.setFrameOrigin(NSPoint(x: point.x - 18, y: point.y))
        self.orderFrontRegardless()
    }

    func hide() {
        self.orderOut(nil)
    }

    private func handleClick() {
        guard !imageView.isHidden else { return } // Prevent double clicks
        
        let text = selectedText
        Diagnostics.log("PopupButton clicked, text length=\(text.count)")

        // Enter loading state
        imageView.isHidden = true
        progressIndicator.startAnimation(nil)

        Task { @MainActor in
            defer {
                // Restore state and hide when done
                self.imageView.isHidden = false
                self.progressIndicator.stopAnimation(nil)
                self.hide()
            }
            
            let service = ServiceFactory.make()
            do {
                let result = try await service.complete(input: text)
                // Copy optimized result to clipboard
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(result.optimized, forType: .string)

                // Save to history
                historyStore.add(HistoryEntry(
                    id: UUID(), timestamp: Date(),
                    input: text,
                    translation: result.translation,
                    optimized: result.optimized
                ))

                // Increase delay to 200ms to allow macOS pasteboard buffer to flush 
                // before target app processes the Cmd+V keystroke (fixes race condition)
                try? await Task.sleep(nanoseconds: 200_000_000) 
                Self.simulatePaste()
                Diagnostics.log("PopupButton: pasted optimized prompt")
            } catch {
                Diagnostics.log("PopupButton error: \(error.localizedDescription)")
            }
        }
    }

    private static func simulatePaste() {
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

// MARK: - ClickableView

private class ClickableView: NSView {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Visual feedback
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            onMouseDown?()
        }
    }
}
