import Foundation
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteFeature
@testable import VoxLiteOutput
@testable import VoxLiteSystem

final class TestStateStore: StateStore {
    var current: VoxState = .idle
    private(set) var transitions: [VoxState] = []

    func transition(to next: VoxState) -> Bool {
        transitions.append(next)
        current = next
        return true
    }
}

struct TestAudioCapture: AudioCaptureServing {
    var startResult: Result<UUID, Error> = .success(UUID())
    var stopElapsedMs: Int = 1_200
    var stopFileContents = Data("stub".utf8)
    var stopResult: Result<Data, Error>?

    func startRecording() throws -> UUID {
        try startResult.get()
    }

    func stopRecording(sessionId: UUID) throws -> Data {
        if let stopResult {
            return try stopResult.get()
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxlite-test-\(sessionId.uuidString)")
            .appendingPathExtension("caf")
        try stopFileContents.write(to: fileURL)
        return "file://\(fileURL.path(percentEncoded: false))|\(stopElapsedMs)".data(using: .utf8) ?? Data()
    }
}

struct TestTranscriber: SpeechTranscribing {
    var result: Result<SpeechTranscription, Error> = .success(
        SpeechTranscription(text: "原始转写文本", latencyMs: 10, usedOnDevice: true)
    )
    var delayNanos: UInt64 = 0

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        if delayNanos > 0 {
            try await Task.sleep(nanoseconds: delayNanos)
        }
        return try result.get()
    }
}

struct TestContextResolver: ContextResolving {
    var context = ContextInfo(bundleId: "com.test.app", appCategory: .communication, inputRole: "textField", locale: "zh_CN")

    func resolveContext() -> ContextInfo {
        context
    }
}

struct TestCleaner: TextCleaning {
    var result: CleanResult

    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        result
    }
}

final class TestInjector: TextInjecting {
    private let results: [InjectResult]
    private(set) var injectedTexts: [String] = []
    private(set) var callCount = 0

    init(results: [InjectResult]) {
        self.results = results
    }

    func injectText(_ text: String) -> InjectResult {
        injectedTexts.append(text)
        let index = min(callCount, results.count - 1)
        callCount += 1
        return results[index]
    }
}

@MainActor
final class TestTranscriberWithObservability: SpeechTranscribing, VoicePipelineStageReporting {
    var stageObserver: VoicePipeline.StageObserver?
    let delayNanos: UInt64
    let latencyMs: Int
    let text: String

    init(delayNanos: UInt64 = 0, latencyMs: Int = 10, text: String = "原始转写文本") {
        self.delayNanos = delayNanos
        self.latencyMs = latencyMs
        self.text = text
    }

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        stageObserver?(.init(stage: .assetCheck, phase: .started))
        stageObserver?(.init(stage: .assetCheck, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        stageObserver?(.init(stage: .assetInstall, phase: .started))
        stageObserver?(.init(stage: .assetInstall, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        stageObserver?(.init(stage: .analyzerCreate, phase: .started))
        stageObserver?(.init(stage: .analyzerCreate, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        stageObserver?(.init(stage: .analyzerWarmup, phase: .started))
        stageObserver?(.init(stage: .analyzerWarmup, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        if delayNanos > 0 {
            try await Task.sleep(nanoseconds: delayNanos)
        }
        return SpeechTranscription(text: text, latencyMs: latencyMs, usedOnDevice: true)
    }
}

@MainActor
final class TestPermissions: PermissionManaging {
    var snapshot: PermissionSnapshot
    private(set) var openedItems: [PermissionItem] = []

    init(snapshot: PermissionSnapshot = PermissionSnapshot(microphoneGranted: true, speechRecognitionGranted: true, accessibilityGranted: true)) {
        self.snapshot = snapshot
    }

    func hasRequiredPermissions() -> Bool {
        snapshot.allGranted
    }

    func currentPermissionSnapshot() -> PermissionSnapshot {
        snapshot
    }

    func requestPermission(_ item: PermissionItem) async -> Bool {
        switch item {
        case .microphone:
            snapshot = .init(microphoneGranted: true, speechRecognitionGranted: snapshot.speechRecognitionGranted, accessibilityGranted: snapshot.accessibilityGranted)
        case .speechRecognition:
            snapshot = .init(microphoneGranted: snapshot.microphoneGranted, speechRecognitionGranted: true, accessibilityGranted: snapshot.accessibilityGranted)
        case .accessibility:
            snapshot = .init(microphoneGranted: snapshot.microphoneGranted, speechRecognitionGranted: snapshot.speechRecognitionGranted, accessibilityGranted: true)
        }
        return true
    }

    func openSystemSettings(for item: PermissionItem) {
        openedItems.append(item)
    }
}

struct TestLogger: LoggerServing {
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) {}
    func error(_ message: String) {}
}

final class TestMetrics: MetricsServing, @unchecked Sendable {
    struct Record: Equatable {
        let event: String
        let success: Bool
        let errorCode: VoxErrorCode?
        let latencyMs: Int
    }

    private(set) var records: [Record] = []
    var percentileResults: [String: [Double: Int]] = [:]

    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {
        records.append(.init(event: event, success: success, errorCode: errorCode, latencyMs: latencyMs))
    }

    func percentile(_ event: String, _ value: Double) -> Int? {
        percentileResults[event]?[value]
    }
}

final class TestHistoryStore: HistoryStore {
    var items: [TranscriptHistoryItem] = []

    func loadHistory() -> [TranscriptHistoryItem] {
        items
    }

    func saveHistory(_ items: [TranscriptHistoryItem]) {
        self.items = items
    }
}

final class TestSkillStore: SkillStore {
    var snapshot: SkillConfigSnapshot

    init(snapshot: SkillConfigSnapshot = FileSkillStore.defaultSnapshot) {
        self.snapshot = snapshot
    }

    func loadSkills() -> SkillConfigSnapshot {
        snapshot
    }

    func saveSkills(_ snapshot: SkillConfigSnapshot) {
        self.snapshot = snapshot
    }
}

final class TestSettingsStore: AppSettingsStore {
    var settings: AppSettings

    init(settings: AppSettings = FileAppSettingsStore.defaultSettings) {
        self.settings = settings
    }

    func loadSettings() -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) {
        self.settings = settings
    }
}

final class TestLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var latestValue = false

    func setEnabled(_ enabled: Bool) {
        latestValue = enabled
    }
}

struct TestAvailabilityProvider: FoundationModelAvailabilityProviding {
    var state: FoundationModelAvailabilityState = .available

    func foundationModelAvailability() -> FoundationModelAvailabilityState {
        state
    }
}

@MainActor
func makePipeline(
    stateMachine: TestStateStore = TestStateStore(),
    audioCapture: TestAudioCapture = TestAudioCapture(),
    transcriber: any SpeechTranscribing = TestTranscriber(),
    contextResolver: any ContextResolving = TestContextResolver(),
    cleaner: any TextCleaning = TestCleaner(
        result: CleanResult(
            cleanText: "清洗后文本",
            confidence: 0.9,
            styleTag: "沟通风格",
            usedFallback: false,
            success: true,
            errorCode: nil,
            latencyMs: 5
        )
    ),
    injector: TestInjector = TestInjector(results: [
        InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 5)
    ]),
    permissions: TestPermissions = TestPermissions(),
    metrics: TestMetrics = TestMetrics(),
    retryPolicy: RetryPolicy = .m2Default
) -> (VoicePipeline, TestStateStore, TestInjector, TestMetrics, TestPermissions) {
    let pipeline = VoicePipeline(
        stateMachine: stateMachine,
        audioCapture: audioCapture,
        transcriber: transcriber,
        contextResolver: contextResolver,
        cleaner: cleaner,
        injector: injector,
        permissions: permissions,
        logger: TestLogger(),
        metrics: metrics,
        retryPolicy: retryPolicy
    )
    return (pipeline, stateMachine, injector, metrics, permissions)
}
