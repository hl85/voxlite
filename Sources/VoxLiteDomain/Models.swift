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
    case remoteAPIError
    case invalidAPIKey
    case rateLimited
    case networkError
    case invalidResponse
    case remoteProviderUnavailable
    case httpsRequired
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
    public static let remoteModelDefault = RetryPolicy(timeoutMs: 10_000, maxRetries: 1)
}

public struct CursorContext: Codable, Equatable, Sendable {
    public let surroundingText: String
    public let selectedText: String?
    public let appBundleId: String
    public let cursorPosition: Int?

    public init(
        surroundingText: String,
        selectedText: String?,
        appBundleId: String,
        cursorPosition: Int?
    ) {
        self.surroundingText = surroundingText
        self.selectedText = selectedText
        self.appBundleId = appBundleId
        self.cursorPosition = cursorPosition
    }
}

public struct PartialTranscription: Sendable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Double?

    public init(text: String, isFinal: Bool, confidence: Double? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

public enum StreamingMode: String, Sendable, CaseIterable {
    case off
    case previewOnly
    case full
}

public struct ContextEnrichment: Codable, Equatable, Sendable {
    public let appName: String?
    public let isEditable: Bool?
    public let focusedRole: String?
    public let vocabularyBias: [String: String]
    public let cursorContext: CursorContext?

    public init(
        appName: String? = nil,
        isEditable: Bool? = nil,
        focusedRole: String? = nil,
        vocabularyBias: [String: String] = [:],
        cursorContext: CursorContext? = nil
    ) {
        self.appName = appName
        self.isEditable = isEditable
        self.focusedRole = focusedRole
        self.vocabularyBias = vocabularyBias
        self.cursorContext = cursorContext
    }

    public var isEmpty: Bool {
        appName == nil && isEditable == nil && focusedRole == nil && vocabularyBias.isEmpty && cursorContext == nil
    }
}

public struct ContextInfo: Equatable, Sendable {
    public let bundleId: String
    public let appCategory: AppCategory
    public let inputRole: String
    public let locale: String
    public let enrich: ContextEnrichment?

    public init(
        bundleId: String,
        appCategory: AppCategory,
        inputRole: String,
        locale: String,
        enrich: ContextEnrichment? = nil
    ) {
        self.bundleId = bundleId
        self.appCategory = appCategory
        self.inputRole = inputRole
        self.locale = locale
        self.enrich = enrich
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
        parts.append(KeyCodeConverter.string(for: keyCode))
        return parts.joined()
    }
}
