import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class HotkeyManager {
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var currentSpec: HotkeySpec?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        setupCarbonEventHandler()
        rebind(to: HotkeyPrefs.load())
    }

    private func setupCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let theEvent = theEvent, let userData = userData else { return OSStatus(eventNotHandledErr) }
            
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(theEvent,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotKeyID)
            
            if err == noErr && hotKeyID.signature == 1337 {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.fire() }
                return noErr // We handled it, stop propagation
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, ptr, nil)
    }

    func rebind(to spec: HotkeySpec) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        currentSpec = spec
        HotkeyPrefs.save(spec)
        
        let hotKeyID = EventHotKeyID(signature: 1337, id: 1)
        var ref: EventHotKeyRef?
        // RegisterEventHotKey registers a global intercept that overrides other apps!
        let err = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        
        if err == noErr {
            hotKeyRef = ref
            Diagnostics.log("Carbon Hotkey registered: \(spec.displayString)")
        } else {
            Diagnostics.log("Failed to register Carbon Hotkey. Error: \(err)")
        }
    }

    func fire() {
        Diagnostics.log("hotkey fired via Carbon")
        action()
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
