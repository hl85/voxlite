import Foundation
import VoxLiteDomain
import VoxLiteSystem

/// Remote speech transcriber that uses OpenAI-compatible Whisper API.
/// Conforms to `SpeechTranscribing` protocol for integration with VoicePipeline.
@available(macOS 26.0, iOS 26.0, *)
@MainActor
public final class RemoteSpeechTranscriber: SpeechTranscribing {
    private let client: any AudioTranscriptionClient
    private let model: String
    private let logger: LoggerServing

    public init(
        client: any AudioTranscriptionClient,
        model: String,
        logger: LoggerServing
    ) {
        self.client = client
        self.model = model
        self.logger = logger
    }

    public func transcribe(
        audioFileURL: URL,
        elapsedMs: Int?
    ) async throws -> SpeechTranscription {
        try await transcribe(audioFileURL: audioFileURL, elapsedMs: elapsedMs, cursorContext: nil)
    }

    public func transcribe(
        audioFileURL: URL,
        elapsedMs: Int?,
        cursorContext: CursorContext?
    ) async throws -> SpeechTranscription {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        logger.info("remote_transcriber begin audioFile=\(audioFileURL.lastPathComponent)")
        
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            logger.warn("remote_transcriber file not found path=\(audioFileURL.path)")
            throw SpeechTranscriptionError.noResult
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)[.size] as? NSNumber)?.intValue ?? -1
        logger.info("remote_transcriber audio file size=\(fileSize) bytes")
        
        let whisperPrompt = cursorContext.flatMap { $0.surroundingText.isEmpty ? nil : $0.surroundingText }

        do {
            let result = try await client.transcribeAudio(
                model: model,
                audioFileURL: audioFileURL,
                prompt: whisperPrompt
            )
            
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            logger.info("remote_transcriber success latency=\(latencyMs)ms textLen=\(result.response.text.count)")
            
            return SpeechTranscription(
                text: result.response.text,
                latencyMs: latencyMs,
                usedOnDevice: false
            )
        } catch let error as OpenAIClientError {
            logger.warn("remote_transcriber error=\(error)")
            throw mapError(error)
        } catch {
            logger.warn("remote_transcriber unexpected error=\(error.localizedDescription)")
            throw VoxErrorCode.remoteAPIError
        }
    }
    
    // MARK: - Private Helpers
    
    /// Maps OpenAIClientError to appropriate VoxErrorCode
    private func mapError(_ error: OpenAIClientError) -> VoxErrorCode {
        switch error {
        case .invalidAPIKey:
            return .invalidAPIKey
        case .rateLimited:
            return .rateLimited
        case .networkError:
            return .networkError
        case .apiError:
            return .remoteAPIError
        case .invalidResponse:
            return .invalidResponse
        case .encodingError:
            return .remoteAPIError
        case .cancelled:
            return .timeout
        }
    }
}
