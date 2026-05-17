import AppKit
import Carbon.HIToolbox
import Foundation

struct HotkeySpec: Codable, Equatable, Sendable {
    var modifiers: UInt32
    var keyCode: UInt32

    static let `default` = HotkeySpec(
        modifiers: UInt32(controlKey) | UInt32(optionKey),
        keyCode: UInt32(kVK_ANSI_P)
    )

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(HotkeySpec.keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command)  { c |= UInt32(cmdKey) }
        if flags.contains(.option)   { c |= UInt32(optionKey) }
        if flags.contains(.control)  { c |= UInt32(controlKey) }
        if flags.contains(.shift)    { c |= UInt32(shiftKey) }
        return c
    }

    static func keyName(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space:        return "Space"
        case kVK_Return:       return "Return"
        case kVK_Tab:          return "Tab"
        case kVK_Delete:       return "Delete"
        case kVK_ForwardDelete:return "Fwd Delete"
        case kVK_Escape:       return "Esc"
        case kVK_LeftArrow:    return "←"
        case kVK_RightArrow:   return "→"
        case kVK_UpArrow:      return "↑"
        case kVK_DownArrow:    return "↓"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key \(code)"
        }
    }
}

enum HotkeyPrefs {
    private static let key = "hotkeyV1"

    static func load() -> HotkeySpec {
        guard let data = UserDefaults.standard.data(forKey: key),
              let spec = try? JSONDecoder().decode(HotkeySpec.self, from: data) else {
            return .default
        }
        return spec
    }

    static func save(_ spec: HotkeySpec) {
        if let data = try? JSONEncoder().encode(spec) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
