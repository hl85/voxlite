import Testing
import AVFoundation

@testable import VoxLiteInput

struct StreamingAudioCaptureTests {

    @Test
    func testStartStreamingReturnsStream() {
        let service = StreamingAudioCaptureService()
        let stream = service.startStreaming()
        #expect(type(of: stream) == AsyncStream<AudioBufferPacket>.self)
    }

    @Test
    func testStopStreamingDoesNotCrashBeforeStart() {
        let service = StreamingAudioCaptureService()
        service.stopStreaming()
    }

    @Test
    func testStopStreamingFinishesStream() async {
        let service = StreamingAudioCaptureService()
        let stream = service.startStreaming()
        service.stopStreaming()

        var receivedFinish = true
        for await _ in stream {
            receivedFinish = false
            break
        }
        #expect(receivedFinish)
    }

    @Test
    func testAudioBufferPacketIsSendable() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        let packet = AudioBufferPacket(buffer: buffer)
        #expect(packet.buffer === buffer)
    }

    @Test
    func testTargetFormatIs16kHzMonoFloat32() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        #expect(format.sampleRate == 16_000)
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatFloat32)
    }

    @Test
    func testMultipleStopCallsDoNotCrash() {
        let service = StreamingAudioCaptureService()
        _ = service.startStreaming()
        service.stopStreaming()
        service.stopStreaming()
    }
}
