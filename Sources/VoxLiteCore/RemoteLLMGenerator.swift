import Foundation
import VoxLiteDomain
import VoxLiteSystem

@MainActor
public final class RemoteLLMGenerator: PromptGenerating {
    private let client: OpenAIClient
    private let model: String
    private let logger: LoggerServing?
    
    public init(client: OpenAIClient, model: String, logger: LoggerServing? = nil) {
        self.client = client
        self.model = model
        self.logger = logger
    }
    
    public func generateText(from prompt: String) async throws -> String {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let messages = [ChatMessage(role: "user", content: prompt)]
        
        do {
            let result = try await client.chatCompletion(
                model: model,
                messages: messages
            )
            
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            
            guard let content = result.response.choices.first?.message.content else {
                logger?.warn("remote_llm empty response choices")
                throw PromptGenerationError.emptyResult
            }
            
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                logger?.warn("remote_llm empty trimmed content")
                throw PromptGenerationError.emptyResult
            }
            
            logMetadata(statusCode: 200, latencyMs: latencyMs)
            
            return trimmed
        } catch let error as OpenAIClientError {
            throw throwUnavailable(error: error)
        } catch {
            logger?.error("remote_llm unexpected error: \(error.localizedDescription)")
            throw PromptGenerationError.unavailable
        }
    }
    
    public func availabilityState() -> FoundationModelAvailabilityState {
        return .available
    }
    
    private func throwUnavailable(error: OpenAIClientError) -> PromptGenerationError {
        switch error {
        case .invalidAPIKey:
            logger?.warn("remote_llm invalid API key")
            return PromptGenerationError.unavailable
        case .rateLimited:
            logger?.warn("remote_llm rate limited")
            return PromptGenerationError.unavailable
        case .apiError(let statusCode, _):
            logger?.warn("remote_llm API error: \(statusCode)")
            return PromptGenerationError.unavailable
        case .networkError(let underlying):
            logger?.warn("remote_llm network error: \(underlying)")
            return PromptGenerationError.unavailable
        case .invalidResponse:
            logger?.warn("remote_llm invalid response")
            return PromptGenerationError.unavailable
        case .encodingError:
            logger?.warn("remote_llm encoding error")
            return PromptGenerationError.unavailable
        case .cancelled:
            logger?.warn("remote_llm cancelled")
            return PromptGenerationError.unavailable
        }
    }
    
    private func logMetadata(statusCode: Int, latencyMs: Int) {
        logger?.info("remote_llm model=\(model) status=\(statusCode) latency=\(latencyMs)ms")
    }
}
