import Foundation
import VoxLiteDomain
import VoxLiteSystem

// MARK: - Error Types

public enum OpenAIClientError: Error, Equatable, Sendable {
    case invalidAPIKey
    case rateLimited
    case apiError(statusCode: Int, body: String)
    case networkError(underlying: String)
    case invalidResponse
    case encodingError
    case cancelled
}

// MARK: - Request/Response DTOs

public struct ChatMessage: Codable, Sendable {
    public let role: String
    public let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
}

public struct ChatCompletionResponse: Codable, Sendable {
    public let choices: [Choice]
    
    public struct Choice: Codable, Sendable {
        public let message: ChatMessage
    }
}

public struct TranscriptionResponse: Codable, Sendable {
    public let text: String
}

public struct ModelsListResponse: Codable, Sendable {
    public let data: [ModelInfo]
    
    public struct ModelInfo: Codable, Sendable {
        public let id: String
    }
}

// MARK: - Result Types with Latency

public struct ChatCompletionResult: Sendable {
    public let response: ChatCompletionResponse
    public let latencyMs: Int
}

public struct TranscriptionResult: Sendable {
    public let response: TranscriptionResponse
    public let latencyMs: Int
}

public struct ModelsListResult: Sendable {
    public let response: ModelsListResponse
    public let latencyMs: Int
}

// MARK: - OpenAIClient

@MainActor
public final class OpenAIClient: Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let urlSession: URLSession
    private let logger: LoggerServing?
    
    private static let timeoutInterval: TimeInterval = 30.0
    
    public init(baseURL: URL, apiKey: String, logger: LoggerServing? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.logger = logger
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.timeoutInterval
        config.timeoutIntervalForResource = Self.timeoutInterval
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Chat Completions
    
    public func chatCompletion(
        model: String,
        messages: [ChatMessage],
        temperature: Double? = nil
    ) async throws -> ChatCompletionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let request = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: temperature
        )
        
        let url = baseURL.appendingPathComponent("chat/completions")
        let (data, response) = try await performRequest(
            url: url,
            method: "POST",
            body: request,
            contentType: "application/json"
        )
        
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        
        try handleHTTPError(httpResponse: httpResponse, data: data)
        
        do {
            let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            logMetadata(endpoint: "/chat/completions", statusCode: httpResponse.statusCode, latencyMs: latencyMs)
            return ChatCompletionResult(response: completionResponse, latencyMs: latencyMs)
        } catch {
            throw OpenAIClientError.invalidResponse
        }
    }
    
    // MARK: - Audio Transcriptions
    
    public func transcribeAudio(
        model: String,
        audioFileURL: URL,
        prompt: String? = nil
    ) async throws -> TranscriptionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw OpenAIClientError.networkError(underlying: "Audio file not found")
        }
        
        let url = baseURL.appendingPathComponent("audio/transcriptions")
        
        // Build multipart/form-data request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeoutInterval
        
        // Set authorization header
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Build multipart body
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model field
        guard let modelField = "--\(boundary)\r\n".data(using: .utf8),
              let modelDisposition = "Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8),
              let modelValue = "\(model)\r\n".data(using: .utf8) else {
            throw OpenAIClientError.encodingError
        }
        body.append(modelField)
        body.append(modelDisposition)
        body.append(modelValue)
        
        // Add file field
        guard let audioData = try? Data(contentsOf: audioFileURL) else {
            throw OpenAIClientError.networkError(underlying: "Failed to read audio file")
        }
        
        let fileName = audioFileURL.lastPathComponent
        guard let fileField = "--\(boundary)\r\n".data(using: .utf8),
              let fileDisposition = "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8),
              let contentType = "Content-Type: audio/\(audioFileURL.pathExtension)\r\n\r\n".data(using: .utf8),
              let newline = "\r\n".data(using: .utf8) else {
            throw OpenAIClientError.encodingError
        }
        body.append(fileField)
        body.append(fileDisposition)
        body.append(contentType)
        body.append(audioData)
        body.append(newline)
        
        if let prompt, prompt.isEmpty == false {
            guard let promptField = "--\(boundary)\r\n".data(using: .utf8),
                  let promptDisposition = "Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8),
                  let promptValue = "\(prompt)\r\n".data(using: .utf8) else {
                throw OpenAIClientError.encodingError
            }
            body.append(promptField)
            body.append(promptDisposition)
            body.append(promptValue)
        }

        // Close boundary
        guard let closeBoundary = "--\(boundary)--\r\n".data(using: .utf8) else {
            throw OpenAIClientError.encodingError
        }
        body.append(closeBoundary)
        
        request.httpBody = body
        
        let (data, response) = try await urlSession.data(for: request)
        
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        
        try handleHTTPError(httpResponse: httpResponse, data: data)
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            logMetadata(endpoint: "/audio/transcriptions", statusCode: httpResponse.statusCode, latencyMs: latencyMs)
            return TranscriptionResult(response: transcriptionResponse, latencyMs: latencyMs)
        } catch {
            throw OpenAIClientError.invalidResponse
        }
    }
    
    // MARK: - List Models
    
    public func listModels() async throws -> ModelsListResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let url = baseURL.appendingPathComponent("models")
        let (data, response) = try await performRequest(
            url: url,
            method: "GET",
            body: Optional<Int>.none,
            contentType: nil
        )
        
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        
        try handleHTTPError(httpResponse: httpResponse, data: data)
        
        do {
            let modelsResponse = try JSONDecoder().decode(ModelsListResponse.self, from: data)
            logMetadata(endpoint: "/models", statusCode: httpResponse.statusCode, latencyMs: latencyMs)
            return ModelsListResult(response: modelsResponse, latencyMs: latencyMs)
        } catch {
            throw OpenAIClientError.invalidResponse
        }
    }
    
    // MARK: - Private Helpers
    
    private func performRequest<T: Codable>(
        url: URL,
        method: String,
        body: T?,
        contentType: String?
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.timeoutInterval
        
        // Set authorization header
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Set content type if provided and body exists
        if let contentType = contentType, body != nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        // Encode body if present
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        do {
            return try await urlSession.data(for: request)
        } catch let error as NSError where error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorCancelled:
                throw OpenAIClientError.cancelled
            case NSURLErrorTimedOut:
                throw OpenAIClientError.networkError(underlying: "Request timed out")
            case NSURLErrorNotConnectedToInternet:
                throw OpenAIClientError.networkError(underlying: "No internet connection")
            default:
                throw OpenAIClientError.networkError(underlying: error.localizedDescription)
            }
        } catch {
            throw OpenAIClientError.networkError(underlying: error.localizedDescription)
        }
    }
    
    private func handleHTTPError(httpResponse: HTTPURLResponse, data: Data) throws {
        let statusCode = httpResponse.statusCode
        let body = String(data: data, encoding: .utf8) ?? ""
        
        switch statusCode {
        case 200...299:
            return // Success
        case 401:
            throw OpenAIClientError.invalidAPIKey
        case 429:
            throw OpenAIClientError.rateLimited
        default:
            throw OpenAIClientError.apiError(statusCode: statusCode, body: body)
        }
    }
    
    private func logMetadata(endpoint: String, statusCode: Int, latencyMs: Int) {
        logger?.info("openai_client endpoint=\(endpoint) status=\(statusCode) latency=\(latencyMs)ms")
    }
}

// MARK: - AudioTranscriptionClient Protocol

@MainActor
public protocol AudioTranscriptionClient: Sendable {
    func transcribeAudio(model: String, audioFileURL: URL, prompt: String?) async throws -> TranscriptionResult
}

extension OpenAIClient: AudioTranscriptionClient {}

// MARK: - Data Extensions for Multipart Form

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}