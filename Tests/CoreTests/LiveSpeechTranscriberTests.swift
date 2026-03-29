import Testing
import AVFoundation
@testable import VoxLiteCore
@testable import VoxLiteDomain

struct LiveSpeechTranscriberTests {

    @Test
    func testStartStreamingReturnsStream() {
        let transcriber = LiveSpeechTranscriber()
        let stream = transcriber.startStreaming()
        #expect(type(of: stream) == AsyncStream<PartialTranscription>.self)
    }

    @Test
    func testStopStreamingBeforeStartDoesNotCrash() async {
        let transcriber = LiveSpeechTranscriber()
        await transcriber.stopStreaming()
    }

    @Test
    func testStopStreamingEndsStream() async {
        let transcriber = LiveSpeechTranscriber()
        let stream = transcriber.startStreaming()
        await transcriber.stopStreaming()

        // 流结束后 for await 应立即退出，不应挂起
        var receivedAny = false
        for await _ in stream {
            receivedAny = true
            break
        }
        _ = receivedAny
    }

    @Test
    func testAppendBufferBeforeStartDoesNotCrash() {
        let transcriber = LiveSpeechTranscriber()
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        transcriber.appendBuffer(buffer)
    }

    @Test
    func testMultipleStartStopCyclesDoNotCrash() async {
        let transcriber = LiveSpeechTranscriber()
        let stream1 = transcriber.startStreaming()
        await transcriber.stopStreaming()
        let stream2 = transcriber.startStreaming()
        await transcriber.stopStreaming()

        #expect(type(of: stream1) == AsyncStream<PartialTranscription>.self)
        #expect(type(of: stream2) == AsyncStream<PartialTranscription>.self)
    }

    @Test
    func testDefaultLocaleInitializer() {
        let defaultTranscriber = LiveSpeechTranscriber()
        let explicitTranscriber = LiveSpeechTranscriber(locale: Locale(identifier: "zh-CN"))

        let stream1 = defaultTranscriber.startStreaming()
        let stream2 = explicitTranscriber.startStreaming()

        #expect(type(of: stream1) == AsyncStream<PartialTranscription>.self)
        #expect(type(of: stream2) == AsyncStream<PartialTranscription>.self)
    }

    @Test
    func testConformsToStreamingTranscribingProtocol() {
        let transcriber: any StreamingTranscribing = LiveSpeechTranscriber()
        let stream = transcriber.startStreaming()
        #expect(type(of: stream) == AsyncStream<PartialTranscription>.self)
    }

    @Test
    func testPartialTranscriptionIsFinalSemantics() {
        let partial = PartialTranscription(text: "正在说话", isFinal: false, confidence: 0.8)
        let finalResult = PartialTranscription(text: "说话结束", isFinal: true, confidence: 0.95)

        #expect(partial.isFinal == false)
        #expect(partial.text == "正在说话")
        #expect(finalResult.isFinal == true)
        #expect(finalResult.text == "说话结束")
    }

    @Test
    func testStopStreamingIsAsyncAndAwaitable() async {
        let transcriber = LiveSpeechTranscriber()
        _ = transcriber.startStreaming()
        await transcriber.stopStreaming()
    }

    @Test
    func testAppendBufferAfterStartDoesNotCrash() async {
        let transcriber = LiveSpeechTranscriber()
        _ = transcriber.startStreaming()

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 512

        transcriber.appendBuffer(buffer)
        await transcriber.stopStreaming()
    }

    @Test
    func testCustomLocaleInitializer() {
        let enTranscriber = LiveSpeechTranscriber(locale: Locale(identifier: "en-US"))
        let stream = enTranscriber.startStreaming()
        #expect(type(of: stream) == AsyncStream<PartialTranscription>.self)
    }
}
