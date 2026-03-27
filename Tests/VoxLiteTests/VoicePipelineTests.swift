import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain

@MainActor
struct VoicePipelineTests {
    @Test
    func startRecording_withoutMicrophonePermission_throwsPermissionError() throws {
        let permissions = TestPermissions(
            snapshot: .init(microphoneGranted: false, speechRecognitionGranted: true, accessibilityGranted: true)
        )
        let (pipeline, stateMachine, _, _, _) = makePipeline(permissions: permissions)

        do {
            _ = try pipeline.startRecording()
            Issue.record("Expected microphone permission error")
        } catch let error as VoxErrorCode {
            #expect(error == .permissionMicrophoneDenied)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(stateMachine.current == .failed)
    }

    @Test
    func stopRecordingAndProcess_whenCleanerFails_fallsBackToTranscript() async throws {
        let cleaner = TestCleaner(
            result: CleanResult(
                cleanText: "",
                confidence: 0,
                styleTag: "failed",
                usedFallback: false,
                success: false,
                errorCode: .cleaningUnavailable,
                latencyMs: 5
            )
        )
        let (pipeline, stateMachine, injector, metrics, _) = makePipeline(cleaner: cleaner)
        let sessionId = try pipeline.startRecording()

        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(result.clean.cleanText == "原始转写文本")
        #expect(result.clean.usedFallback)
        #expect(result.clean.styleTag == "仅转录")
        #expect(injector.injectedTexts == ["原始转写文本"])
        #expect(stateMachine.current == .done)
        #expect(metrics.records.contains(where: { $0.event == "pipeline.clean.fallback" && $0.success }))
    }

    @Test
    func stopRecordingAndProcess_whenInjectFailsOnce_retriesAndSucceeds() async throws {
        let injector = TestInjector(results: [
            .init(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: 5),
            .init(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 5)
        ])
        let (pipeline, stateMachine, _, _, _) = makePipeline(injector: injector)
        let sessionId = try pipeline.startRecording()

        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(result.inject.success)
        #expect(injector.callCount == 2)
        #expect(stateMachine.current == .done)
    }

    @Test
    func stopRecordingAndProcess_whenTranscriptionTimesOut_throwsTimeout() async throws {
        let transcriber = TestTranscriber(
            result: .success(SpeechTranscription(text: "超时文本", latencyMs: 3_501, usedOnDevice: true))
        )
        let (pipeline, stateMachine, _, metrics, _) = makePipeline(transcriber: transcriber)
        let sessionId = try pipeline.startRecording()

        do {
            _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)
            Issue.record("Expected timeout")
        } catch let error as VoxErrorCode {
            #expect(error == .timeout)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(stateMachine.current == .failed)
        #expect(metrics.records.contains(where: { $0.event == "pipeline.timeout" && $0.errorCode == .timeout }))
    }
}
