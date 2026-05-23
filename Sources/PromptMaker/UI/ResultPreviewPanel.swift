import AppKit
import Carbon.HIToolbox

@MainActor
final class ResultPreviewPanel: NSPanel, NSTextFieldDelegate {
    private let historyStore: HistoryStore
    private let textView: NSTextView
    private let followUpField: NSTextField
    private let progressIndicator: NSProgressIndicator
    private let menuButton: NSButton
    private let sendButton: NSButton

    private var currentText: String = ""
    private var inFlight: Bool = false
    private var outsideClickMonitor: Any?

    private let panelWidth: CGFloat = 460
    private let panelHeight: CGFloat = 280
    private let cornerRadius: CGFloat = 14
    private let padding: CGFloat = 16
    private let inputHeight: CGFloat = 36

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore

        // Result text view (no border, no background of its own — blends with panel)
        let scrollFrame = NSRect.zero
        let sv = NSTextView.scrollableTextView()
        sv.frame = scrollFrame
        sv.borderType = .noBorder
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.scrollerStyle = .overlay
        sv.autohidesScrollers = true
        let tv = sv.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 4)
        self.textView = tv

        // Follow-up pill input
        let follow = PillTextField()
        follow.placeholderString = "Refine further…"
        follow.font = NSFont.systemFont(ofSize: 13)
        follow.bezelStyle = .roundedBezel
        follow.isBezeled = false
        follow.isBordered = false
        follow.drawsBackground = false
        follow.focusRingType = .none
        self.followUpField = follow

        // Send arrow button (right of input)
        let send = NSButton(frame: .zero)
        send.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")
        send.bezelStyle = .circular
        send.isBordered = false
        send.imagePosition = .imageOnly
        send.contentTintColor = .controlAccentColor
        self.sendButton = send

        // Loading indicator (overlaps send button when inFlight)
        let pi = NSProgressIndicator(frame: .zero)
        pi.style = .spinning
        pi.controlSize = .small
        pi.isDisplayedWhenStopped = false
        self.progressIndicator = pi

        // Top-right ⋯ menu button (paste/close)
        let menu = NSButton(frame: .zero)
        menu.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Actions")
        menu.bezelStyle = .circular
        menu.isBordered = false
        menu.imagePosition = .imageOnly
        menu.contentTintColor = .secondaryLabelColor
        self.menuButton = menu

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.hasShadow = true
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.minSize = NSSize(width: 340, height: 200)

        // Solid opaque background with rounded corners
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        bg.autoresizingMask = [.width, .height]
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bg.layer?.cornerRadius = cornerRadius
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 0.5
        bg.layer?.borderColor = NSColor.separatorColor.cgColor

        // Layout
        let menuSize: CGFloat = 22
        menu.frame = NSRect(x: panelWidth - padding - menuSize, y: panelHeight - padding - menuSize,
                            width: menuSize, height: menuSize)
        menu.autoresizingMask = [.minXMargin, .minYMargin]

        let inputAreaY: CGFloat = padding
        let inputAreaHeight: CGFloat = inputHeight
        let textAreaY = inputAreaY + inputAreaHeight + 12
        let textAreaHeight = panelHeight - textAreaY - padding - menuSize - 4
        sv.frame = NSRect(x: padding, y: textAreaY, width: panelWidth - padding * 2, height: textAreaHeight)
        sv.autoresizingMask = [.width, .height]

        // Pill input container
        let pill = PillContainerView(frame: NSRect(x: padding, y: inputAreaY,
                                                   width: panelWidth - padding * 2, height: inputAreaHeight))
        pill.autoresizingMask = [.width, .maxYMargin]
        pill.wantsLayer = true
        pill.layer?.cornerRadius = inputAreaHeight / 2
        pill.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.separatorColor.cgColor

        let sendSize: CGFloat = 26
        follow.frame = NSRect(x: 14, y: (inputAreaHeight - 20) / 2,
                              width: pill.frame.width - sendSize - 28, height: 20)
        follow.autoresizingMask = [.width]

        send.frame = NSRect(x: pill.frame.width - sendSize - 5, y: (inputAreaHeight - sendSize) / 2,
                            width: sendSize, height: sendSize)
        send.autoresizingMask = [.minXMargin]

        pi.frame = send.frame
        pi.autoresizingMask = [.minXMargin]

        pill.addSubview(follow)
        pill.addSubview(send)
        pill.addSubview(pi)

        bg.addSubview(sv)
        bg.addSubview(pill)
        bg.addSubview(menu)

        self.contentView = bg

        send.target = self
        send.action = #selector(handleFollowUp)
        menu.target = self
        menu.action = #selector(showActionsMenu(_:))
        follow.target = self
        follow.action = #selector(handleFollowUp)
        follow.delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        handleDismiss()
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            Task { @MainActor in self.handleDismiss() }
            return true
        }
        return false
    }

    func showResult(_ text: String, near point: NSPoint) {
        self.currentText = text
        self.textView.string = text
        self.followUpField.stringValue = ""

        let origin = NSPoint(x: point.x - frame.width / 2, y: point.y - frame.height - 8)
        setFrameOrigin(clampToScreen(origin: origin))
        makeKeyAndOrderFront(nil)

        installOutsideClickMonitor()
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handleDismiss() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    @objc private func showActionsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let pasteItem = NSMenuItem(title: "Paste to source app", action: #selector(handlePaste), keyEquivalent: "")
        pasteItem.target = self
        let copyItem = NSMenuItem(title: "Copy", action: #selector(handleCopy), keyEquivalent: "")
        copyItem.target = self
        let closeItem = NSMenuItem(title: "Close", action: #selector(handleDismiss), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(pasteItem)
        menu.addItem(copyItem)
        menu.addItem(.separator())
        menu.addItem(closeItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func handlePaste() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(currentText, forType: .string)
        removeOutsideClickMonitor()
        orderOut(nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            PopupButton.simulatePaste()
        }
    }

    @objc private func handleCopy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(currentText, forType: .string)
    }

    @objc private func handleDismiss() {
        removeOutsideClickMonitor()
        orderOut(nil)
    }

    @objc private func handleFollowUp() {
        guard !inFlight else { return }
        let instruction = followUpField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        let input = currentText
        Diagnostics.log("ResultPreview follow-up: instruction.len=\(instruction.count)")

        inFlight = true
        followUpField.isEnabled = false
        sendButton.isHidden = true
        progressIndicator.startAnimation(nil)

        Task { @MainActor in
            let service = ServiceFactory.make()
            let output: String?
            do {
                output = try await service.customComplete(input: input, instruction: instruction)
            } catch {
                Diagnostics.log("ResultPreview follow-up error: \(error.localizedDescription)")
                output = nil
            }

            self.inFlight = false
            self.followUpField.isEnabled = true
            self.sendButton.isHidden = false
            self.progressIndicator.stopAnimation(nil)

            guard let out = output, !out.isEmpty else { return }

            self.currentText = out
            self.textView.string = out
            self.followUpField.stringValue = ""

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(out, forType: .string)

            self.historyStore.add(HistoryEntry(
                id: UUID(), timestamp: Date(),
                input: "[\(instruction)]\n\(input)",
                translation: "",
                optimized: out
            ))
        }
    }

    private func clampToScreen(origin: NSPoint) -> NSPoint {
        guard let screen = NSScreen.main?.visibleFrame else { return origin }
        var x = origin.x
        var y = origin.y
        if x + frame.width > screen.maxX { x = screen.maxX - frame.width - 8 }
        if x < screen.minX { x = screen.minX + 8 }
        if y < screen.minY { y = screen.minY + 8 }
        if y + frame.height > screen.maxY { y = screen.maxY - frame.height - 8 }
        return NSPoint(x: x, y: y)
    }
}

// MARK: - Pill subviews

private final class PillContainerView: NSView {}

private final class PillTextField: NSTextField {}
