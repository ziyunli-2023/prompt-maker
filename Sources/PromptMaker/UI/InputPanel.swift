import AppKit
import Carbon.HIToolbox

@MainActor
final class InputPanel: NSPanel, NSTextFieldDelegate {
    private let historyStore: HistoryStore
    private let resultPanel: ResultPreviewPanel
    private var selectedText: String = ""
    private var anchorPoint: NSPoint = .zero
    private var isStandalone: Bool = false

    private let textField: NSTextField
    private let sendButton: NSButton
    private let progressIndicator: NSProgressIndicator
    private var inFlight: Bool = false

    private let panelWidth: CGFloat = 480
    private let panelHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 14
    private let padding: CGFloat = 10
    private let inputHeight: CGFloat = 36

    init(historyStore: HistoryStore, resultPanel: ResultPreviewPanel) {
        self.historyStore = historyStore
        self.resultPanel = resultPanel

        let tf = InputPillTextField()
        tf.placeholderString = "Enter to optimize · type instruction to translate / summarize / rewrite…"
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.isBezeled = false
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        self.textField = tf

        let send = NSButton(frame: .zero)
        send.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")
        send.bezelStyle = .circular
        send.isBordered = false
        send.imagePosition = .imageOnly
        send.contentTintColor = .controlAccentColor
        self.sendButton = send

        let pi = NSProgressIndicator(frame: .zero)
        pi.style = .spinning
        pi.controlSize = .small
        pi.isDisplayedWhenStopped = false
        self.progressIndicator = pi

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false

        // Solid opaque background with rounded corners
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        bg.autoresizingMask = [.width, .height]
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bg.layer?.cornerRadius = cornerRadius
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 0.5
        bg.layer?.borderColor = NSColor.separatorColor.cgColor

        // Pill container
        let pill = InputPillContainerView(frame: NSRect(x: padding, y: (panelHeight - inputHeight) / 2,
                                                        width: panelWidth - padding * 2, height: inputHeight))
        pill.autoresizingMask = [.width]
        pill.wantsLayer = true
        pill.layer?.cornerRadius = inputHeight / 2
        pill.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.separatorColor.cgColor

        let sendSize: CGFloat = 26
        tf.frame = NSRect(x: 14, y: (inputHeight - 20) / 2,
                          width: pill.frame.width - sendSize - 28, height: 20)
        tf.autoresizingMask = [.width]

        send.frame = NSRect(x: pill.frame.width - sendSize - 5, y: (inputHeight - sendSize) / 2,
                            width: sendSize, height: sendSize)
        send.autoresizingMask = [.minXMargin]

        pi.frame = send.frame
        pi.autoresizingMask = [.minXMargin]

        pill.addSubview(tf)
        pill.addSubview(send)
        pill.addSubview(pi)
        bg.addSubview(pill)
        self.contentView = bg

        tf.target = self
        tf.action = #selector(handleSubmit)
        tf.delegate = self
        send.target = self
        send.action = #selector(handleSubmit)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            Task { @MainActor in self.hide() }
            return true
        }
        return false
    }

    func showAt(point: NSPoint, selectedText: String) {
        self.isStandalone = false
        self.selectedText = selectedText
        self.anchorPoint = point
        self.textField.stringValue = ""
        self.textField.placeholderString = "Enter to optimize · type instruction to translate / summarize / rewrite…"
        self.setFrameOrigin(NSPoint(x: point.x - frame.width / 2, y: point.y - frame.height - 4))
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.textField.becomeFirstResponder()
    }

    func showStandalone() {
        self.isStandalone = true
        self.selectedText = ""
        self.textField.stringValue = ""
        self.textField.placeholderString = "Ask anything…  ⏎ to send"

        // Center horizontally on the active screen, vertically biased upward
        // so the result panel has room to expand below it.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let originX = screen.midX - frame.width / 2
        let originY = screen.minY + screen.height * 0.62
        self.anchorPoint = NSPoint(x: screen.midX, y: originY + frame.height + 8)
        self.setFrameOrigin(NSPoint(x: originX, y: originY))
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.textField.becomeFirstResponder()
    }

    func toggleStandalone() {
        if self.isVisible && self.isStandalone {
            self.hide()
        } else {
            self.showStandalone()
        }
    }

    func hide() {
        orderOut(nil)
    }

    @objc private func handleSubmit() {
        guard !inFlight else { return }
        let instruction = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = selectedText
        let standalone = isStandalone
        Diagnostics.log("InputPanel submit: standalone=\(standalone), instruction.len=\(instruction.count), text.len=\(text.count)")

        // Standalone Q&A: the field IS the prompt, no selected text involved.
        if standalone {
            guard !instruction.isEmpty else { return }
            inFlight = true
            textField.isEnabled = false
            sendButton.isHidden = true
            progressIndicator.startAnimation(nil)

            let anchor = self.anchorPoint
            Task { @MainActor in
                let service = ServiceFactory.make()
                let output: String?
                do {
                    output = try await service.freeformComplete(prompt: instruction)
                } catch {
                    Diagnostics.log("InputPanel freeform error: \(error.localizedDescription)")
                    output = nil
                }

                self.finishInput()

                guard let out = output, !out.isEmpty else {
                    self.hide()
                    return
                }

                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(out, forType: .string)

                self.historyStore.add(HistoryEntry(
                    id: UUID(), timestamp: Date(),
                    input: instruction,
                    translation: "",
                    optimized: out
                ))

                self.hide()
                self.resultPanel.showResult(out, near: anchor)
            }
            return
        }

        inFlight = true
        textField.isEnabled = false
        sendButton.isHidden = true
        progressIndicator.startAnimation(nil)

        Task { @MainActor in
            let service = ServiceFactory.make()

            if instruction.isEmpty {
                let defaultInstruction = "翻译成中文"
                do {
                    let out = try await service.customComplete(input: text, instruction: defaultInstruction)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(out, forType: .string)

                    self.historyStore.add(HistoryEntry(
                        id: UUID(), timestamp: Date(),
                        input: "[\(defaultInstruction)]\n\(text)",
                        translation: "",
                        optimized: out
                    ))

                    self.finishInput()
                    let anchor = self.anchorPoint
                    self.hide()
                    self.resultPanel.showResult(out, near: anchor)
                    Diagnostics.log("InputPanel: default translate to Chinese, shown")
                } catch {
                    Diagnostics.log("InputPanel default error: \(error.localizedDescription)")
                    self.finishInput()
                    self.hide()
                }
                return
            }

            let output: String?
            do {
                output = try await service.customComplete(input: text, instruction: instruction)
            } catch {
                Diagnostics.log("InputPanel custom error: \(error.localizedDescription)")
                output = nil
            }

            self.finishInput()

            guard let out = output, !out.isEmpty else {
                self.hide()
                return
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(out, forType: .string)

            self.historyStore.add(HistoryEntry(
                id: UUID(), timestamp: Date(),
                input: "[\(instruction)]\n\(text)",
                translation: "",
                optimized: out
            ))

            let anchor = self.anchorPoint
            self.hide()
            self.resultPanel.showResult(out, near: anchor)
        }
    }

    private func finishInput() {
        inFlight = false
        textField.isEnabled = true
        sendButton.isHidden = false
        progressIndicator.stopAnimation(nil)
    }
}

// MARK: - Pill subviews

private final class InputPillContainerView: NSView {}

private final class InputPillTextField: NSTextField {}
