import AVFoundation
import Speech
import VoxLiteDomain
import os.log

/// 基于 SFSpeechRecognizer 的实时流式转写服务。
/// 端侧优先（requiresOnDeviceRecognition = true），适合录音过程中的实时预览。
public final class LiveSpeechTranscriber: StreamingTranscribing, @unchecked Sendable {

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let logger = Logger(subsystem: "ai.holoo.voxlite", category: "LiveSpeechTranscriber")

    public init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    public func startStreaming() -> AsyncStream<PartialTranscription> {
        stopCurrentTask()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            logger.warning("LiveSpeechTranscriber: recognizer unavailable or nil, returning empty stream")
            return AsyncStream { $0.finish() }
        }

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            logger.warning("LiveSpeechTranscriber: speech recognition not authorized, status=\(String(describing: authStatus))")
            return AsyncStream { $0.finish() }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.recognitionRequest = request

        return AsyncStream<PartialTranscription> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else {
                    continuation.finish()
                    return
                }

                if let error = error {
                    self.logger.warning("LiveSpeechTranscriber: recognition error=\(error.localizedDescription)")
                    continuation.finish()
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    return
                }

                guard let result else { return }

                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                let confidence = result.bestTranscription.segments.last.map { Double($0.confidence) }

                let partial = PartialTranscription(text: text, isFinal: isFinal, confidence: confidence)
                continuation.yield(partial)

                if isFinal {
                    continuation.finish()
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                }
            }
        }
    }

    public func stopStreaming() async {
        stopCurrentTask()
    }

    public func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    private func stopCurrentTask() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}
