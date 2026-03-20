import AVFoundation
import Foundation
import VoxLiteDomain
import VoxLiteSystem

public final class AudioCaptureService: AudioCaptureServing {
    private var recorder: AVAudioRecorder?
    private let logger: LoggerServing
    private var sessionId: UUID?
    private var startedAt: Date?
    private var recordingURL: URL?
    private var stoppedAt: Date?
    private let restartCooldownMs: Int
    private let minimumRecordingMs: Int

    public init(
        logger: LoggerServing,
        restartCooldownMs: Int = 250,
        minimumRecordingMs: Int = 120
    ) {
        self.logger = logger
        self.restartCooldownMs = restartCooldownMs
        self.minimumRecordingMs = minimumRecordingMs
    }

    public func startRecording() throws -> UUID {
        if sessionId != nil || recorder != nil {
            logger.warn("recording start ignored while previous session is still active")
            throw VoxErrorCode.recordingUnavailable
        }
        if let stoppedAt {
            let intervalMs = Int(Date().timeIntervalSince(stoppedAt) * 1000)
            if intervalMs < restartCooldownMs {
                logger.warn("recording start throttled due to fast restart")
                throw VoxErrorCode.recordingUnavailable
            }
        }
        let id = UUID()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxlite-\(id.uuidString)")
            .appendingPathExtension("caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let recorder = try AVAudioRecorder(url: tmp, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            logger.error("recording start failed by AVAudioRecorder.record false")
            throw VoxErrorCode.recordingUnavailable
        }
        self.recorder = recorder
        self.recordingURL = tmp
        sessionId = id
        startedAt = Date()
        logger.info("recording started session id=\(id.uuidString) file=\(tmp.lastPathComponent)")
        return id
    }

    public func stopRecording(sessionId: UUID) throws -> Data {
        guard self.sessionId == sessionId, let recorder else {
            logger.warn("recording stop failed due to mismatched session")
            throw VoxErrorCode.recordingUnavailable
        }
        recorder.stop()
        self.recorder = nil

        let elapsed = Int((Date().timeIntervalSince(startedAt ?? Date())) * 1000)
        if elapsed < minimumRecordingMs {
            self.sessionId = nil
            self.startedAt = nil
            self.stoppedAt = Date()
            let removeURL = recordingURL
            self.recordingURL = nil
            if let removeURL {
                try? FileManager.default.removeItem(at: removeURL)
            }
            logger.warn("recording dropped because duration is too short elapsed=\(elapsed)ms")
            throw VoxErrorCode.recordingUnavailable
        }
        let path = recordingURL?.path(percentEncoded: false) ?? ""
        let payload = "file://\(path)|\(elapsed)".data(using: .utf8) ?? Data()
        self.sessionId = nil
        self.startedAt = nil
        self.stoppedAt = Date()
        self.recordingURL = nil
        logger.info("recording stopped session id=\(sessionId.uuidString) elapsed=\(elapsed)ms")
        return payload
    }
}
