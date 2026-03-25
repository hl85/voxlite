import Carbon
import Foundation

public enum VoxState: String, Equatable, Sendable {
    case idle
    case recording
    case processing
    case injecting
    case done
    case failed
}

public enum VoxErrorCode: String, Error, Equatable, Sendable {
    case permissionDenied
    case permissionMicrophoneDenied
    case permissionSpeechDenied
    case permissionAccessibilityDenied
    case recordingUnavailable
    case transcriptionUnavailable
    case contextUnavailable
    case cleaningUnavailable
    case injectionFailed
    case timeout
    case retryExhausted
    case unknown
}

public enum PermissionItem: String, Equatable, Sendable, CaseIterable {
    case microphone
    case speechRecognition
    case accessibility
}

public struct PermissionSnapshot: Equatable, Sendable {
    public let microphoneGranted: Bool
    public let speechRecognitionGranted: Bool
    public let accessibilityGranted: Bool

    public init(microphoneGranted: Bool, speechRecognitionGranted: Bool, accessibilityGranted: Bool) {
        self.microphoneGranted = microphoneGranted
        self.speechRecognitionGranted = speechRecognitionGranted
        self.accessibilityGranted = accessibilityGranted
    }

    public var allGranted: Bool {
        microphoneGranted && speechRecognitionGranted && accessibilityGranted
    }
}

public struct RetryPolicy: Equatable, Sendable {
    public let timeoutMs: Int
    public let maxRetries: Int

    public init(timeoutMs: Int, maxRetries: Int) {
        self.timeoutMs = timeoutMs
        self.maxRetries = maxRetries
    }

    public static let m2Default = RetryPolicy(timeoutMs: 3_000, maxRetries: 1)
}

public struct ContextInfo: Equatable, Sendable {
    public let bundleId: String
    public let appCategory: AppCategory
    public let inputRole: String
    public let locale: String

    public init(bundleId: String, appCategory: AppCategory, inputRole: String, locale: String) {
        self.bundleId = bundleId
        self.appCategory = appCategory
        self.inputRole = inputRole
        self.locale = locale
    }
}

public enum AppCategory: String, Codable, Hashable, Equatable, Sendable {
    case communication
    case development
    case writing
    case general
}

public enum CleaningMode: String, Codable, Equatable, Sendable {
    case ruleOnly
    case llmWithFallback
}

public enum SettingsSection: String, Codable, Equatable, Sendable {
    case general
    case microphone
    case speechRecognition
    case accessibility
}

public enum ErrorAction: Codable, Equatable, Sendable {
    case goToSettings(SettingsSection)
}

public struct ErrorDetail: Codable, Equatable, Sendable {
    public let summary: String
    public let detail: String
    public let errorCode: String?
    public let recommendedAction: ErrorAction?

    public init(summary: String, detail: String, errorCode: String? = nil, recommendedAction: ErrorAction? = nil) {
        self.summary = summary
        self.detail = detail
        self.errorCode = errorCode
        self.recommendedAction = recommendedAction
    }
}

public struct TranscriptResult: Equatable, Sendable {
    public let text: String
    public let success: Bool
    public let errorCode: VoxErrorCode?
    public let latencyMs: Int

    public init(text: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {
        self.text = text
        self.success = success
        self.errorCode = errorCode
        self.latencyMs = latencyMs
    }
}

public struct SpeechTranscription: Equatable, Sendable {
    public let text: String
    public let latencyMs: Int
    public let usedOnDevice: Bool

    public init(text: String, latencyMs: Int, usedOnDevice: Bool) {
        self.text = text
        self.latencyMs = latencyMs
        self.usedOnDevice = usedOnDevice
    }
}

public enum SpeechTranscriptionError: Error, Equatable, Sendable {
    case permissionDenied
    case localeNotSupported(String)
    case transcriberUnavailable
    case assetUnavailable
    case noResult
    case timedOut
    case underlying(String)
}

public struct CleanResult: Equatable, Sendable {
    public let cleanText: String
    public let confidence: Double
    public let styleTag: String
    public let usedFallback: Bool
    public let success: Bool
    public let errorCode: VoxErrorCode?
    public let latencyMs: Int

    public init(
        cleanText: String,
        confidence: Double,
        styleTag: String,
        usedFallback: Bool = false,
        success: Bool,
        errorCode: VoxErrorCode?,
        latencyMs: Int
    ) {
        self.cleanText = cleanText
        self.confidence = confidence
        self.styleTag = styleTag
        self.usedFallback = usedFallback
        self.success = success
        self.errorCode = errorCode
        self.latencyMs = latencyMs
    }
}

public struct InjectResult: Equatable, Sendable {
    public let success: Bool
    public let usedClipboardFallback: Bool
    public let errorCode: VoxErrorCode?
    public let latencyMs: Int

    public init(success: Bool, usedClipboardFallback: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {
        self.success = success
        self.usedClipboardFallback = usedClipboardFallback
        self.errorCode = errorCode
        self.latencyMs = latencyMs
    }
}

public struct ProcessResult: Equatable, Sendable {
    public let sessionId: UUID
    public let transcript: TranscriptResult
    public let context: ContextInfo
    public let clean: CleanResult
    public let inject: InjectResult
    public let totalLatencyMs: Int

    public init(
        sessionId: UUID,
        transcript: TranscriptResult,
        context: ContextInfo,
        clean: CleanResult,
        inject: InjectResult,
        totalLatencyMs: Int
    ) {
        self.sessionId = sessionId
        self.transcript = transcript
        self.context = context
        self.clean = clean
        self.inject = inject
        self.totalLatencyMs = totalLatencyMs
    }
}

public struct HotKeyConfiguration: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt32

    public init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let fnKeyCode: UInt16 = 63

    public static let defaultConfiguration = HotKeyConfiguration(
        keyCode: fnKeyCode,
        modifiers: 0
    )

    public static let controlModifierMask: UInt32 = UInt32(controlKey)
    public static let optionModifierMask: UInt32 = UInt32(optionKey)
    public static let shiftModifierMask: UInt32 = UInt32(shiftKey)
    public static let commandModifierMask: UInt32 = UInt32(cmdKey)

    public var displayString: String {
        var parts: [String] = []
        if modifiers & Self.controlModifierMask != 0 {
            parts.append("^")
        }
        if modifiers & Self.optionModifierMask != 0 {
            parts.append("⌥")
        }
        if modifiers & Self.shiftModifierMask != 0 {
            parts.append("⇧")
        }
        if modifiers & Self.commandModifierMask != 0 {
            parts.append("⌘")
        }
        if let keyChar = keyCodeToString(keyCode) {
            parts.append(keyChar)
        }
        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_Period: return "."
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_ANSI_Grave: return "`"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Escape"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F3: return "F3"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F11: return "F11"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F10: return "F10"
        case kVK_F12: return "F12"
        case kVK_F4: return "F4"
        case kVK_F2: return "F2"
        case kVK_F1: return "F1"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        case kVK_Function: return "Fn"
        default: return nil
        }
    }
}
