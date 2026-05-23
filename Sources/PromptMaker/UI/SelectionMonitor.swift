import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class SelectionMonitor {
    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private let popupButton: PopupButton
    
    // For drag/click detection
    private var lastMouseDownPos: NSPoint = .zero
    private var lastMouseDownTime: Date = Date()
    private var isPotentialSelection: Bool = false

    init(historyStore: HistoryStore, inputPanel: InputPanel, resultPanel: ResultPreviewPanel) {
        self.popupButton = PopupButton(historyStore: historyStore, inputPanel: inputPanel, resultPanel: resultPanel)
        let enabled = UserDefaults.standard.object(forKey: "selectionPopupEnabled") as? Bool ?? true
        if enabled { startMonitoring() }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { startMonitoring() } else { stopMonitoring(); popupButton.hide() }
    }

    // MARK: - Monitor lifecycle

    private func startMonitoring() {
        guard mouseUpMonitor == nil else { return }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            // Capture position synchronously — NSEvent.mouseLocation read inside
            // the Task can lag behind reality if the main actor is busy.
            let pos = NSEvent.mouseLocation
            let clickCount = event.clickCount
            Task { @MainActor in self?.handleMouseUp(upPos: pos, clickCount: clickCount) }
        }

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let pos = NSEvent.mouseLocation
            let now = Date()
            Task { @MainActor in
                self?.popupButton.hide()
                self?.lastMouseDownPos = pos
                self?.lastMouseDownTime = now
            }
        }
        Diagnostics.log("SelectionMonitor started")
    }

    private func stopMonitoring() {
        if let m = mouseUpMonitor  { NSEvent.removeMonitor(m); mouseUpMonitor  = nil }
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        Diagnostics.log("SelectionMonitor stopped")
    }

    // MARK: - Selection detection

    private func handleMouseUp(upPos: NSPoint, clickCount: Int) {
        let dx = upPos.x - lastMouseDownPos.x
        let dy = upPos.y - lastMouseDownPos.y
        let distance = sqrt(dx*dx + dy*dy)

        // If it's a drag (>3 points) or a double/triple click, it's a potential selection
        isPotentialSelection = (distance > 3.0) || (clickCount > 1)

        // Short delay to let selection settle. We carry the mouseUp position
        // through — by the time this fires, NSEvent.mouseLocation may have
        // drifted (e.g. trackpad released and hand moved away).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.checkForSelection(anchor: upPos)
        }
    }

    private func checkForSelection(anchor: NSPoint) {
        var text = Self.getSelectedTextWithAX()

        if (text == nil || text!.isEmpty) && isPotentialSelection {
            Diagnostics.log("AX returned empty, but drag/double-click detected. Trying Cmd+C fallback...")
            text = Self.getSelectedTextWithCmdC()
        }

        guard let text = text, text.count >= 2 else {
            popupButton.hide()
            return
        }
        // Always show next to where the user released the mouse — consistent
        // across native apps and web pages, no AX-bounds surprises.
        let position = NSPoint(x: anchor.x + 16, y: anchor.y + 16)
        popupButton.showAt(point: position, selectedText: text)
    }

    // MARK: - AX helpers

    nonisolated static func getSelectedTextWithAX() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        let err1 = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref)
        guard err1 == .success, let el = ref else {
            Diagnostics.log("AX Failed: could not get focused UI element. Error: \(err1.rawValue)")
            return nil
        }
        
        var textRef: CFTypeRef?
        let err2 = AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &textRef)
        guard err2 == .success, let str = textRef as? String else {
            Diagnostics.log("AX Failed: could not get selected text attribute. Error: \(err2.rawValue)")
            return nil
        }
        
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        Diagnostics.log("AX Success: got selected text length \(trimmed.count)")
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func getSelectedTextWithCmdC() -> String? {
        let pb = NSPasteboard.general
        let oldString = pb.string(forType: .string)
        pb.clearContents()
        
        // Simulate Cmd+C
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        down?.flags = CGEventFlags.maskCommand
        up?.flags = CGEventFlags.maskCommand
        down?.post(tap: CGEventTapLocation.cghidEventTap)
        up?.post(tap: CGEventTapLocation.cghidEventTap)
        
        // Wait for clipboard to update
        Thread.sleep(forTimeInterval: 0.1)
        
        let newString = pb.string(forType: .string)
        
        // Restore old clipboard
        if let old = oldString {
            pb.clearContents()
            pb.setString(old, forType: .string)
        }
        
        let trimmed = newString?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            Diagnostics.log("Cmd+C Fallback Success: got text length \(t.count)")
            return t
        }
        Diagnostics.log("Cmd+C Fallback Failed")
        return nil
    }
}
