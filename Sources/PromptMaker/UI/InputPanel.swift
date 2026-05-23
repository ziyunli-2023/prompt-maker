import AppKit
import Carbon.HIToolbox

@MainActor
final class InputPanel: NSPanel, NSTextFieldDelegate {
    private let historyStore: HistoryStore
    private let resultPanel: ResultPreviewPanel
    private var selectedText: String = ""
    private var anchorPoint: NSPoint = .zero

    private let textField: NSTextField
    private let sendButton: NSButton
    private let progressIndicator: NSProgressIndicator
    private var inFlight: Bool = false

    private let panelWidth: CGFloat = 380
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

        // Vibrancy background with rounded corners
        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor

        // Pill container
        let pill = InputPillContainerView(frame: NSRect(x: padding, y: (panelHeight - inputHeight) / 2,
                                                        width: panelWidth - padding * 2, height: inputHeight))
        pill.autoresizingMask = [.width]
        pill.wantsLayer = true
        pill.layer?.cornerRadius = inputHeight / 2
        pill.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6).cgColor
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
        blur.addSubview(pill)
        self.contentView = blur

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
        self.selectedText = selectedText
        self.anchorPoint = point
        self.textField.stringValue = ""
        self.setFrameOrigin(NSPoint(x: point.x - frame.width / 2, y: point.y - frame.height - 4))
        self.makeKeyAndOrderFront(nil)
        self.textField.becomeFirstResponder()
    }

    func hide() {
        orderOut(nil)
    }

    @objc private func handleSubmit() {
        guard !inFlight else { return }
        let instruction = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = selectedText
        Diagnostics.log("InputPanel submit: instruction.len=\(instruction.count), text.len=\(text.count)")

        inFlight = true
        textField.isEnabled = false
        sendButton.isHidden = true
        progressIndicator.startAnimation(nil)

        Task { @MainActor in
            let service = ServiceFactory.make()

            if instruction.isEmpty {
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

                    self.finishInput()
                    self.hide()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    PopupButton.simulatePaste()
                    Diagnostics.log("InputPanel: default optimize, pasted")
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

private final class InputPillContainerView: NSView {
    override var allowsVibrancy: Bool { true }
}

private final class InputPillTextField: NSTextField {
    override var allowsVibrancy: Bool { true }
}
