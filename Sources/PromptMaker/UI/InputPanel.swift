import AppKit
import Carbon.HIToolbox

@MainActor
final class InputPanel: NSPanel, NSTextFieldDelegate {
    private let historyStore: HistoryStore
    private let resultPanel: ResultPreviewPanel
    private var selectedText: String = ""
    private var anchorPoint: NSPoint = .zero

    private let textField: NSTextField
    private let progressIndicator: NSProgressIndicator
    private var inFlight: Bool = false

    init(historyStore: HistoryStore, resultPanel: ResultPreviewPanel) {
        self.historyStore = historyStore
        self.resultPanel = resultPanel

        let width: CGFloat = 360
        let height: CGFloat = 40

        let tf = NSTextField(frame: NSRect(x: 10, y: 8, width: width - 50, height: 24))
        tf.placeholderString = "回车=优化;输入指令=翻译/总结/改写…"
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.bezelStyle = .roundedBezel
        tf.focusRingType = .none
        tf.isBordered = true
        tf.drawsBackground = true
        tf.backgroundColor = .textBackgroundColor
        self.textField = tf

        let pi = NSProgressIndicator(frame: NSRect(x: width - 32, y: 12, width: 16, height: 16))
        pi.style = .spinning
        pi.controlSize = .small
        pi.isDisplayedWhenStopped = false
        self.progressIndicator = pi

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 0.5
        container.addSubview(tf)
        container.addSubview(pi)
        self.contentView = container

        tf.target = self
        tf.action = #selector(handleSubmit)
        tf.delegate = self
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            Task { @MainActor in self.hide() }
            return true
        }
        return false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        hide()
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
        progressIndicator.startAnimation(nil)

        Task { @MainActor in
            let service = ServiceFactory.make()

            if instruction.isEmpty {
                // Empty input = default optimize, direct paste, no preview window
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

            // Custom instruction → call customComplete, show preview
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
        progressIndicator.stopAnimation(nil)
    }
}
