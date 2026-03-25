// KeyCodeConverter.swift
// VoxLiteDomain
//
// Comprehensive virtual key code to display string mapping.
// Reference: Apple Technical Note TN2092 — Virtual Key Codes
// https://developer.apple.com/library/archive/technotes/tn2092/_index.html
//
// Key code constants are sourced from Carbon.HIToolbox/Events.h (kVK_* constants).

import Carbon.HIToolbox

/// Converts macOS virtual key codes (UInt16) to human-readable display strings.
///
/// Uses kVK_* constants from Carbon.HIToolbox as defined in Apple Technical Note TN2092.
/// The `string(for:)` method NEVER returns an optional and NEVER returns an empty string —
/// unknown keycodes fall back to "Key <decimal>" format.
public enum KeyCodeConverter {

    // MARK: - Public API

    /// Returns a human-readable display string for the given virtual key code.
    ///
    /// - Parameter keyCode: A macOS virtual key code (UInt16).
    /// - Returns: A non-empty display string. Known keys return their label (e.g. "A", "F1", "Space").
    ///   Unknown keys return "Key <decimal>" (e.g. "Key 255").
    ///
    /// - Note: Based on Apple Technical Note TN2092 virtual key code table.
    ///   Uses kVK_* constants from Carbon.HIToolbox.
    public static func string(for keyCode: UInt16) -> String {
        switch Int(keyCode) {

        // MARK: Letters (kVK_ANSI_A … kVK_ANSI_Z)
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

        // MARK: Numbers & Symbols (kVK_ANSI_0 … kVK_ANSI_9, punctuation)
        case kVK_ANSI_0:            return "0"
        case kVK_ANSI_1:            return "1"
        case kVK_ANSI_2:            return "2"
        case kVK_ANSI_3:            return "3"
        case kVK_ANSI_4:            return "4"
        case kVK_ANSI_5:            return "5"
        case kVK_ANSI_6:            return "6"
        case kVK_ANSI_7:            return "7"
        case kVK_ANSI_8:            return "8"
        case kVK_ANSI_9:            return "9"
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_Grave:        return "`"
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Slash:        return "/"

        // MARK: Function Keys (kVK_F1 … kVK_F20)
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"

        // MARK: Modifiers
        case kVK_Command:      return "⌘"
        case kVK_RightCommand: return "⌘"
        case kVK_Shift:        return "⇧"
        case kVK_RightShift:   return "⇧"
        case kVK_Option:       return "⌥"
        case kVK_RightOption:  return "⌥"
        case kVK_Control:      return "^"
        case kVK_RightControl: return "^"
        case kVK_CapsLock:     return "⇪"
        case kVK_Function:     return "Fn"

        // MARK: Navigation & Editing
        case kVK_Return:        return "Return"
        case kVK_Tab:           return "Tab"
        case kVK_Space:         return "Space"
        case kVK_Delete:        return "Delete"          // Backspace (top-left)
        case kVK_ForwardDelete: return "⌦"               // Forward Delete (fn+Delete on laptops)
        case kVK_Escape:        return "Escape"
        case kVK_Home:          return "Home"
        case kVK_End:           return "End"
        case kVK_PageUp:        return "PageUp"
        case kVK_PageDown:      return "PageDown"
        case kVK_Help:          return "Help"            // Insert/Help key

        // MARK: Arrow Keys
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"

        // MARK: Keypad (kVK_ANSI_Keypad*)
        case kVK_ANSI_Keypad0:       return "Num0"
        case kVK_ANSI_Keypad1:       return "Num1"
        case kVK_ANSI_Keypad2:       return "Num2"
        case kVK_ANSI_Keypad3:       return "Num3"
        case kVK_ANSI_Keypad4:       return "Num4"
        case kVK_ANSI_Keypad5:       return "Num5"
        case kVK_ANSI_Keypad6:       return "Num6"
        case kVK_ANSI_Keypad7:       return "Num7"
        case kVK_ANSI_Keypad8:       return "Num8"
        case kVK_ANSI_Keypad9:       return "Num9"
        case kVK_ANSI_KeypadDecimal:  return "Num."
        case kVK_ANSI_KeypadPlus:     return "Num+"
        case kVK_ANSI_KeypadMinus:    return "Num-"
        case kVK_ANSI_KeypadMultiply: return "Num*"
        case kVK_ANSI_KeypadDivide:   return "Num/"
        case kVK_ANSI_KeypadEquals:   return "Num="
        case kVK_ANSI_KeypadEnter:    return "NumEnter"
        case kVK_ANSI_KeypadClear:    return "NumClear"

        // MARK: Media / Special
        // 0x6E — Menu key; no official kVK_Menu constant in Carbon.HIToolbox.
        // TN2092 lists this as "Application / Context Menu".
        case 0x6E: return "▤"          // Menu key (Context Menu / Application key)
        case kVK_VolumeUp:   return "🔊"
        case kVK_VolumeDown: return "🔉"
        case kVK_Mute:       return "🔇"

        // MARK: JIS Keyboard keys (kVK_JIS_*)
        case kVK_JIS_Yen:        return "¥"
        case kVK_JIS_Underscore: return "_"
        case kVK_JIS_KeypadComma: return "Num,"
        case kVK_JIS_Eisu:       return "英数"
        case kVK_JIS_Kana:       return "かな"

        // MARK: Unknown — fallback NEVER returns empty
        // TN2092: unrecognised codes displayed as "Key <decimal>" for debuggability.
        default: return "Key \(keyCode)"
        }
    }
}
