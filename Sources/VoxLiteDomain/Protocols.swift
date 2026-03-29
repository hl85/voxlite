import AVFoundation
import Foundation

public struct AudioBufferPacket: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer

    public init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

public protocol StreamingAudioCapturing: Sendable {
    func startStreaming() -> AsyncStream<AudioBufferPacket>
    func stopStreaming()
}

public protocol StateStore: AnyObject {
    var current: VoxState { get }
    func transition(to next: VoxState) -> Bool
}

public protocol AudioCaptureServing {
    func startRecording() throws -> UUID
    func stopRecording(sessionId: UUID) throws -> Data
}

@MainActor
public protocol SpeechTranscribing {
    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription
}

public protocol ContextResolving {
    func resolveContext() -> ContextInfo
}

public protocol CursorContextReading: Sendable {
    func readContext() async throws -> CursorContext?
}

public protocol StreamingTranscribing: Sendable {
    func startStreaming() -> AsyncStream<PartialTranscription>
    func stopStreaming() async
    func appendBuffer(_ buffer: AVAudioPCMBuffer)
}

@MainActor
public protocol TextCleaning {
    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult
}

public protocol TextInjecting {
    func injectText(_ text: String) -> InjectResult
}

/// 注入策略：按顺序尝试注入方案，首个成功即返回；全部失败则返回最后一个结果
public protocol InjectionStrategyServing: TextInjecting {
    var strategies: [TextInjecting] { get }
}

@MainActor
public protocol PermissionManaging {
    func hasRequiredPermissions() -> Bool
    func currentPermissionSnapshot() -> PermissionSnapshot
    func requestPermission(_ item: PermissionItem) async -> Bool
    func openSystemSettings(for item: PermissionItem)
}

public protocol LoggerServing: Sendable {
    func debug(_ message: String)
    func info(_ message: String)
    func warn(_ message: String)
    func error(_ message: String)
}

public protocol MetricsServing: Sendable {
    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int)
    func percentile(_ event: String, _ value: Double) -> Int?
}

public protocol HistoryStore {
    func loadHistory() -> [TranscriptHistoryItem]
    func saveHistory(_ items: [TranscriptHistoryItem])
}

public protocol SkillStore {
    func loadSkills() -> SkillConfigSnapshot
    func saveSkills(_ snapshot: SkillConfigSnapshot)
}

public protocol AppSettingsStore {
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings)
}

public protocol LaunchAtLoginManaging {
    func setEnabled(_ enabled: Bool)
}

public protocol KeychainStoring: Sendable {
    func store(_ value: String, forKey key: String) throws
    func retrieve(forKey key: String) throws -> String?
    func delete(forKey key: String) throws
}
