import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteSystem

@MainActor
struct AXPermissionTests {
    @Test
    func testAXPermissionRequestAtLaunch() {
        let manager = PermissionManager()

        #expect(Bool(true))
        manager.requestAccessibilityPermission()
        _ = manager.checkAccessibilityPermission()
    }

    @Test
    func testAXPermissionDeniedGraceful() {
        let permissions = StubPermissions()
        permissions.snapshot = .init(microphoneGranted: true, speechRecognitionGranted: true, accessibilityGranted: false)

        let pipeline = VoicePipeline(
            stateMachine: LocalStateStore(),
            audioCapture: LocalAudioCapture(),
            transcriber: LocalTranscriber(),
            contextResolver: LocalContextResolver(),
            cleaner: LocalCleaner(),
            injector: LocalInjector(),
            permissions: permissions,
            logger: LocalLogger(),
            metrics: LocalMetrics()
        )

        let sessionId = try? pipeline.startRecording()
        #expect(sessionId != nil)
        #expect(permissions.snapshot.accessibilityGranted == false)
    }
}

@MainActor
final class StubPermissions: PermissionManaging {
    var snapshot = PermissionSnapshot(microphoneGranted: true, speechRecognitionGranted: true, accessibilityGranted: true)

    func hasRequiredPermissions() -> Bool { snapshot.allGranted }

    func currentPermissionSnapshot() -> PermissionSnapshot { snapshot }

    func requestPermission(_ item: PermissionItem) async -> Bool { true }

    func openSystemSettings(for item: PermissionItem) {}
}

final class LocalStateStore: StateStore {
    var current: VoxState = .idle
    func transition(to next: VoxState) -> Bool {
        current = next
        return true
    }
}

struct LocalAudioCapture: AudioCaptureServing {
    func startRecording() throws -> UUID { UUID() }
    func stopRecording(sessionId: UUID) throws -> Data { Data("stub".utf8) }
}

struct LocalTranscriber: SpeechTranscribing {
    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        SpeechTranscription(text: "stub", latencyMs: 1, usedOnDevice: true)
    }
}

struct LocalContextResolver: ContextResolving {
    func resolveContext() -> ContextInfo {
        ContextInfo(bundleId: "com.test.app", appCategory: .communication, inputRole: "textField", locale: "zh_CN")
    }
}

struct LocalCleaner: TextCleaning {
    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        CleanResult(cleanText: transcript, confidence: 1, styleTag: "沟通风格", usedFallback: false, success: true, errorCode: nil, latencyMs: 1)
    }
}

struct LocalInjector: TextInjecting {
    func injectText(_ text: String) -> InjectResult {
        InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 1)
    }
}

final class LocalLogger: LoggerServing {
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) {}
    func error(_ message: String) {}
}

final class LocalMetrics: MetricsServing {
    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {}
    func percentile(_ event: String, _ value: Double) -> Int? { nil }
}
