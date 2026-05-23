import AppKit
import Carbon.HIToolbox

@MainActor
final class ResultPreviewPanel: NSPanel, NSTextFieldDelegate {
    private let historyStore: HistoryStore
    private let textView: NSTextView
    private let followUpField: NSTextField
    private let progressIndicator: NSProgressIndicator
    private let pasteButton: NSButton
    private let closeButton: NSButton

    private var currentText: String = ""
    private var inFlight: Bool = false
    private var outsideClickMonitor: Any?

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore

        let width: CGFloat = 460
        let height: CGFloat = 300

        let sv = NSTextView.scrollableTextView()
        sv.frame = NSRect(x: 12, y: 92, width: width - 24, height: height - 110)
        sv.autoresizingMask = [.width, .height]
        sv.borderType = .lineBorder
        let tv = sv.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        self.textView = tv

        let follow = NSTextField(frame: NSRect(x: 12, y: 50, width: width - 56, height: 26))
        follow.placeholderString = "继续改写… 回车提交"
        follow.font = NSFont.systemFont(ofSize: 13)
        follow.bezelStyle = .roundedBezel
        follow.focusRingType = .none
        follow.autoresizingMask = [.width, .maxYMargin]
        self.followUpField = follow

        let pi = NSProgressIndicator(frame: NSRect(x: width - 36, y: 54, width: 18, height: 18))
        pi.style = .spinning
        pi.controlSize = .small
        pi.isDisplayedWhenStopped = false
        pi.autoresizingMask = [.minXMargin, .maxYMargin]
        self.progressIndicator = pi

        let paste = NSButton(title: "粘贴", target: nil, action: nil)
        paste.frame = NSRect(x: width - 90, y: 10, width: 78, height: 28)
        paste.bezelStyle = .rounded
        paste.keyEquivalent = "\r"
        paste.autoresizingMask = [.minXMargin, .maxYMargin]
        self.pasteButton = paste

        let close = NSButton(title: "关闭", target: nil, action: nil)
        close.frame = NSRect(x: width - 180, y: 10, width: 78, height: 28)
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        close.autoresizingMask = [.minXMargin, .maxYMargin]
        self.closeButton = close

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        self.title = "结果"
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.hasShadow = true
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.autoresizingMask = [.width, .height]
        container.addSubview(sv)
        container.addSubview(follow)
        container.addSubview(pi)
        container.addSubview(paste)
        container.addSubview(close)
        self.contentView = container

        paste.target = self
        paste.action = #selector(handlePaste)
        close.target = self
        close.action = #selector(handleDismiss)
        follow.target = self
        follow.action = #selector(handleFollowUp)
        follow.delegate = self
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            Task { @MainActor in self.handleDismiss() }
            return true
        }
        return false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        handleDismiss()
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

    @objc private func handlePaste() {
        removeOutsideClickMonitor()
        orderOut(nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            PopupButton.simulatePaste()
        }
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
