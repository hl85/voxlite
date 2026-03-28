import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain

@MainActor
struct VoicePipelineRetryTests {
    @Test
    func stopRecordingAndProcess_whenInjectFailsOnlyRetriesInjectionStage() async throws {
        let stateMachine = TestStateStore()
        let transcriber = CountingTranscriber()
        let cleaner = CountingCleaner()
        let injector = CountingInjector(results: [
            .init(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: 5),
            .init(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 5)
        ])
        let metrics = TestMetrics()
        let pipeline = VoicePipeline(
            stateMachine: stateMachine,
            audioCapture: TestAudioCapture(),
            transcriber: transcriber,
            contextResolver: TestContextResolver(),
            cleaner: cleaner,
            injector: injector,
            permissions: TestPermissions(),
            logger: TestLogger(),
            metrics: metrics,
            retryPolicy: RetryPolicy(timeoutMs: 3_000, maxRetries: 1)
        )

        let sessionId = try pipeline.startRecording()
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(result.inject.success)
        #expect(transcriber.callCount == 1)
        #expect(cleaner.callCount == 1)
        #expect(injector.callCount == 2)
        #expect(injector.injectedTexts == ["清洗后文本", "清洗后文本"])
        #expect(stateMachine.current == .done)
        #expect(metrics.records.filter { $0.event == "pipeline.stage.transcribe" }.count == 1)
        #expect(metrics.records.filter { $0.event == "pipeline.stage.clean" }.count == 1)
        #expect(metrics.records.filter { $0.event == "pipeline.stage.inject" }.count == 2)
    }

    @Test
    func stopRecordingAndProcess_whenInjectAlreadySucceeded_doesNotWriteTwiceAfterBudgetIsExceeded() async throws {
        let stateMachine = TestStateStore()
        let transcriber = CountingTranscriber()
        let cleaner = CountingCleaner()
        let injector = CountingInjector(results: [
            .init(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 50)
        ])
        let pipeline = VoicePipeline(
            stateMachine: stateMachine,
            audioCapture: TestAudioCapture(),
            transcriber: transcriber,
            contextResolver: TestContextResolver(),
            cleaner: cleaner,
            injector: injector,
            permissions: TestPermissions(),
            logger: TestLogger(),
            metrics: TestMetrics(),
            retryPolicy: RetryPolicy(timeoutMs: 20, maxRetries: 1)
        )

        let sessionId = try pipeline.startRecording()
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(result.inject.success)
        #expect(transcriber.callCount == 1)
        #expect(cleaner.callCount == 1)
        #expect(injector.callCount == 1)
        #expect(injector.injectedTexts == ["清洗后文本"])
        #expect(result.inject.latencyMs == 50)
        #expect(stateMachine.current == .done)
    }
}

@MainActor
private final class CountingTranscriber: SpeechTranscribing {
    private let delayNs: UInt64
    private let transcription: SpeechTranscription
    private(set) var callCount = 0

    init(delayNs: UInt64 = 0, transcription: SpeechTranscription = .init(text: "原始转写文本", latencyMs: 5, usedOnDevice: true)) {
        self.delayNs = delayNs
        self.transcription = transcription
    }

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        callCount += 1
        if delayNs > 0 {
            try? await Task.sleep(nanoseconds: delayNs)
        }
        return transcription
    }
}

@MainActor
private final class CountingCleaner: TextCleaning {
    private let delayNs: UInt64
    private let result: CleanResult
    private(set) var callCount = 0

    init(
        delayNs: UInt64 = 0,
        result: CleanResult = .init(
            cleanText: "清洗后文本",
            confidence: 0.9,
            styleTag: "沟通风格",
            usedFallback: false,
            success: true,
            errorCode: nil,
            latencyMs: 5
        )
    ) {
        self.delayNs = delayNs
        self.result = result
    }

    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        callCount += 1
        if delayNs > 0 {
            try? await Task.sleep(nanoseconds: delayNs)
        }
        return result
    }
}

private final class CountingInjector: TextInjecting {
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
