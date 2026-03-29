import Foundation
import Testing

@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteSystem

@MainActor
struct RemoteSpeechTranscriberTests {

    @Test
    func transcribe_whenFileNotFound_throwsNoResult() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let client = StubAudioTranscriptionClient(result: .success(makeTranscriptionResult("text")))
            let transcriber = RemoteSpeechTranscriber(client: client, model: "whisper-1", logger: TestLogger())
            let missingURL = URL(fileURLWithPath: "/tmp/nonexistent-voxlite-test.caf")

            await #expect(throws: SpeechTranscriptionError.noResult) {
                try await transcriber.transcribe(audioFileURL: missingURL, elapsedMs: nil)
            }
        }
    }

    @Test
    func transcribe_withCursorContext_passesPromptToClient() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let client = StubAudioTranscriptionClient(result: .success(makeTranscriptionResult("hello")))
            let transcriber = RemoteSpeechTranscriber(client: client, model: "whisper-1", logger: TestLogger())
            let fileURL = try writeTempAudioFile(name: "test-with-prompt")

            let cursor = CursorContext(
                surroundingText: "surrounding text here",
                selectedText: nil,
                appBundleId: "com.test.app",
                cursorPosition: nil
            )

            _ = try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: nil, cursorContext: cursor)

            #expect(client.capturedPrompt == "surrounding text here")
        }
    }

    @Test
    func transcribe_withNilCursorContext_passesNilPromptToClient() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let client = StubAudioTranscriptionClient(result: .success(makeTranscriptionResult("hello")))
            let transcriber = RemoteSpeechTranscriber(client: client, model: "whisper-1", logger: TestLogger())
            let fileURL = try writeTempAudioFile(name: "test-nil-context")

            _ = try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: nil, cursorContext: nil)

            #expect(client.capturedPrompt == nil)
        }
    }

    @Test
    func transcribe_withEmptySurroundingText_passesNilPromptToClient() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let client = StubAudioTranscriptionClient(result: .success(makeTranscriptionResult("hello")))
            let transcriber = RemoteSpeechTranscriber(client: client, model: "whisper-1", logger: TestLogger())
            let fileURL = try writeTempAudioFile(name: "test-empty-surrounding")

            let cursor = CursorContext(
                surroundingText: "",
                selectedText: nil,
                appBundleId: "com.test.app",
                cursorPosition: nil
            )

            _ = try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: nil, cursorContext: cursor)

            #expect(client.capturedPrompt == nil)
        }
    }

    @Test
    func transcribe_whenClientThrowsRateLimited_mapsToRateLimitedError() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let client = StubAudioTranscriptionClient(result: .failure(OpenAIClientError.rateLimited))
            let transcriber = RemoteSpeechTranscriber(client: client, model: "whisper-1", logger: TestLogger())
            let fileURL = try writeTempAudioFile(name: "test-rate-limited")

            await #expect(throws: VoxErrorCode.rateLimited) {
                try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: nil)
            }
        }
    }

    @Test
    func transcribe_whenClientThrowsInvalidAPIKey_mapsToInvalidAPIKeyError() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let client = StubAudioTranscriptionClient(result: .failure(OpenAIClientError.invalidAPIKey))
            let transcriber = RemoteSpeechTranscriber(client: client, model: "whisper-1", logger: TestLogger())
            let fileURL = try writeTempAudioFile(name: "test-invalid-key")

            await #expect(throws: VoxErrorCode.invalidAPIKey) {
                try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: nil)
            }
        }
    }

    @Test
    func transcribe_success_returnsTranscriptionWithUsedOnDeviceFalse() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let client = StubAudioTranscriptionClient(result: .success(makeTranscriptionResult("转写结果")))
            let transcriber = RemoteSpeechTranscriber(client: client, model: "whisper-1", logger: TestLogger())
            let fileURL = try writeTempAudioFile(name: "test-success")

            let result = try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: nil)

            #expect(result.text == "转写结果")
            #expect(result.usedOnDevice == false)
        }
    }
}

// MARK: - Helpers

private func writeTempAudioFile(name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("voxlite-\(name)-\(UUID().uuidString)")
        .appendingPathExtension("caf")
    try Data("stub-audio".utf8).write(to: url)
    return url
}

private func makeTranscriptionResult(_ text: String) -> TranscriptionResult {
    TranscriptionResult(
        response: TranscriptionResponse(text: text),
        latencyMs: 42
    )
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
private final class StubAudioTranscriptionClient: AudioTranscriptionClient {
    private let result: Result<TranscriptionResult, Error>
    private(set) var capturedPrompt: String?

    init(result: Result<TranscriptionResult, Error>) {
        self.result = result
    }

    func transcribeAudio(model: String, audioFileURL: URL, prompt: String?) async throws -> TranscriptionResult {
        capturedPrompt = prompt
        return try result.get()
    }
}
