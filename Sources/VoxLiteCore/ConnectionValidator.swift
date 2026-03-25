import Foundation
import VoxLiteDomain
import VoxLiteSystem

// MARK: - Result Types

public enum ConnectionValidationResult: Sendable {
    case success(models: [String])
    case failure(ConnectionValidationError)
}

public enum ConnectionValidationError: Error, Sendable {
    case invalidAPIKey
    case rateLimited
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case unknown(String)
}

// MARK: - Connection Validator

@MainActor
public final class ConnectionValidator: Sendable {
    private let logger: (any LoggerServing)?
    
    public init(logger: (any LoggerServing)? = nil) {
        self.logger = logger
    }
    
    public func validate(baseURL: URL, apiKey: String) async -> ConnectionValidationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let client = OpenAIClient(baseURL: baseURL, apiKey: apiKey, logger: logger)
        
        do {
            let result = try await client.listModels()
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let modelIds = result.response.data.map(\.id)
            
            logger?.info("connection_validator endpoint=\(baseURL.absoluteString) success=true model_count=\(modelIds.count) latency=\(latencyMs)ms")
            
            return .success(models: modelIds)
        } catch let error as OpenAIClientError {
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            logger?.info("connection_validator endpoint=\(baseURL.absoluteString) success=false latency=\(latencyMs)ms error=\(String(describing: error))")
            
            switch error {
            case .invalidAPIKey:
                return .failure(.invalidAPIKey)
            case .rateLimited:
                return .failure(.rateLimited)
            case .networkError(let underlying):
                return .failure(.networkError(underlying))
            case .apiError(let statusCode, let body):
                return .failure(.apiError(statusCode: statusCode, message: body))
            case .invalidResponse, .encodingError, .cancelled:
                return .failure(.unknown(error.localizedDescription))
            }
        } catch {
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            logger?.info("connection_validator endpoint=\(baseURL.absoluteString) success=false latency=\(latencyMs)ms error=\(error.localizedDescription)")
            
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
