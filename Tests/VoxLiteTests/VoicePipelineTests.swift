import Testing
import AVFoundation
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteInput

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

    @Test
    func hybridPipeline_offMode_behaviorUnchanged() async throws {
        let streamingTranscriber = TestStreamingTranscriber()
        let cursorReader = TestCursorReader()
        let pipeline = makeHybridPipeline(
            streamingMode: .off,
            streamingTranscriber: streamingTranscriber,
            cursorReader: cursorReader
        )
        let sessionId = try pipeline.startRecording()
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(result.transcript.text == "原始转写文本")
        #expect(streamingTranscriber.startCalledCount == 0)
        #expect(cursorReader.readCalledCount == 0)
    }

    @Test
    func hybridPipeline_previewOnly_startsStreamingAndCursorReader() async throws {
        let streamingTranscriber = TestStreamingTranscriber()
        streamingTranscriber.partialResults = [
            PartialTranscription(text: "实时预览", isFinal: false, confidence: 0.8)
        ]
        let cursorReader = TestCursorReader()
        cursorReader.contextToReturn = CursorContext(
            surroundingText: "前置文本",
            selectedText: nil,
            appBundleId: "com.test.app",
            cursorPosition: 10
        )
        let pipeline = makeHybridPipeline(
            streamingMode: .previewOnly,
            streamingTranscriber: streamingTranscriber,
            cursorReader: cursorReader
        )
        let sessionId = try pipeline.startRecording()
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(result.transcript.text == "原始转写文本")
        #expect(cursorReader.readCalledCount == 0, "previewOnly 模式不读取光标上下文")
        #expect(streamingTranscriber.stopCalledCount >= 1)
    }

    @Test
    func hybridPipeline_cursorContextPassedToCleanerViaEnrich() async throws {
        let capturedContexts = ActorBox<[ContextInfo]>([])
        let cursorContext = CursorContext(
            surroundingText: "Hello world",
            selectedText: "world",
            appBundleId: "com.apple.xcode",
            cursorPosition: 11
        )
        let cursorReader = TestCursorReader()
        cursorReader.contextToReturn = cursorContext

        let recordingCleaner = ContextCapturingCleaner(capturedContexts: capturedContexts)
        let pipeline = makeHybridPipeline(
            streamingMode: .full,
            streamingTranscriber: TestStreamingTranscriber(),
            cursorReader: cursorReader,
            cleaner: recordingCleaner
        )

        let sessionId = try pipeline.startRecording()
        _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        let contexts = await capturedContexts.value
        #expect(contexts.count == 1)
        #expect(contexts[0].enrich?.cursorContext == cursorContext)
    }

    @Test
    func hybridPipeline_streamingFailure_doesNotAffectFileTranscription() async throws {
        let streamingTranscriber = TestStreamingTranscriber()
        streamingTranscriber.shouldFailStreaming = true
        let cursorReader = TestCursorReader()

        let pipeline = makeHybridPipeline(
            streamingMode: .previewOnly,
            streamingTranscriber: streamingTranscriber,
            cursorReader: cursorReader
        )
        let sessionId = try pipeline.startRecording()
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(result.transcript.text == "原始转写文本")
        #expect(result.inject.success)
    }

    @Test
    func hybridPipeline_partialResultCallback_receivesPartials() async throws {
        let streamingTranscriber = TestStreamingTranscriber()
        streamingTranscriber.partialResults = [
            PartialTranscription(text: "第一段", isFinal: false, confidence: 0.7),
            PartialTranscription(text: "第一段第二段", isFinal: true, confidence: 0.9)
        ]
        var receivedPartials: [PartialTranscription] = []
        let pipeline = makeHybridPipeline(
            streamingMode: .previewOnly,
            streamingTranscriber: streamingTranscriber,
            cursorReader: TestCursorReader(),
            onPartialTranscription: { partial in
                receivedPartials.append(partial)
            }
        )

        let sessionId = try pipeline.startRecording()
        _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        #expect(receivedPartials.count == 2)
        #expect(receivedPartials[0].text == "第一段")
        #expect(receivedPartials[1].isFinal == true)
    }
}
