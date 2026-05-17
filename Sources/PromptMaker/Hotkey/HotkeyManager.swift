import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class HotkeyManager {
    private weak var panel: FloatingPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentSpec: HotkeySpec?
    private var accessibilityTimer: Timer?
    private var wasAccessibilityTrusted: Bool = false

    init(panel: FloatingPanel) {
        self.panel = panel
        rebind(to: HotkeyPrefs.load())
        startAccessibilityPolling()
    }

    func rebind(to spec: HotkeySpec) {
        teardownMonitors()
        currentSpec = spec
        HotkeyPrefs.save(spec)

        let mask = HotkeySpec.nsFlags(from: spec.modifiers)
        let keyCode = UInt16(spec.keyCode)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Diagnostics.log("global keyDown kc=\(event.keyCode) flags=\(event.modifierFlags.rawValue)")
            guard HotkeyManager.eventMatches(event, modifiers: mask, keyCode: keyCode) else { return }
            Task { @MainActor in self?.fire() }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if HotkeyManager.eventMatches(event, modifiers: mask, keyCode: keyCode) {
                Task { @MainActor in self?.fire() }
                return nil
            }
            return event
        }

        let trusted = AccessibilityHelper.isTrusted
        wasAccessibilityTrusted = trusted
        Diagnostics.log("rebind via NSEvent — keyCode=\(spec.keyCode) mods=\(spec.modifiers) display=\(spec.displayString) accessibilityTrusted=\(trusted)")
    }

    /// Polls for Accessibility permission changes. When permission is newly
    /// granted, re-registers the global monitor so it actually receives events.
    private func startAccessibilityPolling() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibilityChange()
            }
        }
    }

    private func checkAccessibilityChange() {
        let trusted = AccessibilityHelper.isTrusted
        if trusted && !wasAccessibilityTrusted {
            Diagnostics.log("Accessibility permission newly granted — re-registering hotkey monitors")
            if let spec = currentSpec {
                rebind(to: spec)
            }
        }
        wasAccessibilityTrusted = trusted
        // Stop polling once trusted — permission won't be revoked while running
        if trusted {
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
        }
    }

    private func fire() {
        Diagnostics.log("hotkey fired")
        panel?.toggle()
    }

    private func teardownMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
    }

    private static func eventMatches(_ event: NSEvent, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let masked = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return masked.intersection(relevant) == modifiers
    }
}

extension HotkeySpec {
    static func nsFlags(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey)     != 0 { f.insert(.command) }
        if carbon & UInt32(optionKey)  != 0 { f.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { f.insert(.control) }
        if carbon & UInt32(shiftKey)   != 0 { f.insert(.shift) }
        return f
    }
}

enum AccessibilityHelper {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func promptIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
