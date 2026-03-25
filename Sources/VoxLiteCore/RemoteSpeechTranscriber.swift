import Foundation
import VoxLiteDomain
import VoxLiteSystem

/// Remote speech transcriber that uses OpenAI-compatible Whisper API.
/// Conforms to `SpeechTranscribing` protocol for integration with VoicePipeline.
@available(macOS 26.0, iOS 26.0, *)
@MainActor
public final class RemoteSpeechTranscriber: SpeechTranscribing {
    private let client: OpenAIClient
    private let model: String
    private let logger: LoggerServing
    
    /// Creates a new remote speech transcriber.
    /// - Parameters:
    ///   - client: The OpenAI-compatible client for making API requests
    ///   - model: The Whisper model name (e.g., "whisper-large-v3-turbo")
    ///   - logger: Logger for metadata-only logging
    public init(
        client: OpenAIClient,
        model: String,
        logger: LoggerServing
    ) {
        self.client = client
        self.model = model
        self.logger = logger
    }
    
    /// Transcribes an audio file using the remote Whisper API.
    /// - Parameters:
    ///   - audioFileURL: The local file URL of the audio to transcribe
    ///   - elapsedMs: Optional elapsed time hint from previous processing (not used for remote)
    /// - Returns: A `SpeechTranscription` with the transcribed text and metadata
    /// - Throws: `SpeechTranscriptionError` or `VoxErrorCode` on failure
    public func transcribe(
        audioFileURL: URL,
        elapsedMs: Int?
    ) async throws -> SpeechTranscription {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        logger.info("remote_transcriber begin audioFile=\(audioFileURL.lastPathComponent)")
        
        // 1. Verify file exists
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            logger.warn("remote_transcriber file not found path=\(audioFileURL.path)")
            throw SpeechTranscriptionError.noResult
        }
        
        // Get file size for logging
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)[.size] as? NSNumber)?.intValue ?? -1
        logger.info("remote_transcriber audio file size=\(fileSize) bytes")
        
        // 2. Measure latency and call client
        do {
            let result = try await client.transcribeAudio(
                model: model,
                audioFileURL: audioFileURL
            )
            
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            
            // 4. Return SpeechTranscription (usedOnDevice: false for remote)
            logger.info("remote_transcriber success latency=\(latencyMs)ms textLen=\(result.response.text.count)")
            
            return SpeechTranscription(
                text: result.response.text,
                latencyMs: latencyMs,
                usedOnDevice: false
            )
        } catch let error as OpenAIClientError {
            // 5. Map OpenAIClientError to VoxErrorCode
            logger.warn("remote_transcriber error=\(error)")
            throw mapError(error)
        } catch {
            // Unexpected error
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
