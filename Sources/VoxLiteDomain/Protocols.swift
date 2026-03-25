import Foundation

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

@MainActor
public protocol TextCleaning {
    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult
}

public protocol TextInjecting {
    func injectText(_ text: String) -> InjectResult
}

@MainActor
public protocol PermissionManaging {
    func hasRequiredPermissions() -> Bool
    func currentPermissionSnapshot() -> PermissionSnapshot
    func requestPermission(_ item: PermissionItem) async -> Bool
    func openSystemSettings(for item: PermissionItem)
}

public protocol LoggerServing {
    func debug(_ message: String)
    func info(_ message: String)
    func warn(_ message: String)
    func error(_ message: String)
}

public protocol MetricsServing {
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
