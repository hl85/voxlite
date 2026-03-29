import AVFoundation
import Foundation
import VoxLiteDomain

public final class StreamingAudioCaptureService: StreamingAudioCapturing, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var continuation: AsyncStream<AudioBufferPacket>.Continuation?

    public init() {}

    public func startStreaming() -> AsyncStream<AudioBufferPacket> {
        let stream = AsyncStream<AudioBufferPacket> { [weak self] continuation in
            self?.continuation = continuation
            self?.installTap(continuation: continuation)
        }
        return stream
    }

    public func stopStreaming() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        continuation?.finish()
        continuation = nil
    }

    private func installTap(continuation: AsyncStream<AudioBufferPacket>.Continuation) {
        let inputNode = audioEngine.inputNode
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            guard let converter else {
                continuation.yield(AudioBufferPacket(buffer: buffer))
                return
            }
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil {
                continuation.yield(AudioBufferPacket(buffer: converted))
            }
        }

        do {
            try audioEngine.start()
        } catch {
            continuation.finish()
        }
    }
}
