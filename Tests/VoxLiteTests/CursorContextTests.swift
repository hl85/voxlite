import Foundation
import Testing

@testable import VoxLiteDomain

@MainActor
struct CursorContextTests {
    @Test
    func testCursorContextInitialization() {
        let context = CursorContext(
            surroundingText: "line1\nline2\nline3",
            selectedText: "line2",
            appBundleId: "com.test.app",
            cursorPosition: 12
        )

        #expect(context.surroundingText == "line1\nline2\nline3")
        #expect(context.selectedText == "line2")
        #expect(context.appBundleId == "com.test.app")
        #expect(context.cursorPosition == 12)
    }

    @Test
    func testCursorContextEquatable() {
        let lhs = CursorContext(
            surroundingText: "hello world",
            selectedText: nil,
            appBundleId: "com.test.app",
            cursorPosition: nil
        )
        let rhs = CursorContext(
            surroundingText: "hello world",
            selectedText: nil,
            appBundleId: "com.test.app",
            cursorPosition: nil
        )

        #expect(lhs == rhs)
    }

    @Test
    func testPartialTranscriptionInitialization() {
        let transcription = PartialTranscription(text: "hello", isFinal: false, confidence: 0.88)

        #expect(transcription.text == "hello")
        #expect(transcription.isFinal == false)
        #expect(transcription.confidence == 0.88)
    }

    @Test
    func testStreamingModeAllCases() {
        #expect(StreamingMode.allCases == [.off, .previewOnly, .full])
    }

    @Test
    func testCursorContextReadingProtocolMock() async throws {
        let reader = TestCursorContextReader(context: CursorContext(
            surroundingText: "context",
            selectedText: "selected",
            appBundleId: "com.test.app",
            cursorPosition: 4
        ))

        let result = try await reader.readContext()

        #expect(result?.surroundingText == "context")
        #expect(result?.selectedText == "selected")
        #expect(result?.appBundleId == "com.test.app")
        #expect(result?.cursorPosition == 4)
    }

    @Test
    func testStreamingTranscribingProtocolMock() async {
        let transcriber = TestStreamingTranscriber()
        transcriber.partialResults = [
            PartialTranscription(text: "part-1", isFinal: false, confidence: 0.5),
            PartialTranscription(text: "part-2", isFinal: true, confidence: 0.9)
        ]
        let stream = transcriber.startStreaming()

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.text == "part-1")
        #expect(first?.isFinal == false)
        #expect(second?.text == "part-2")
        #expect(second?.isFinal == true)

        await transcriber.stopStreaming()
        #expect(transcriber.didStop)
    }
}

private struct TestCursorContextReader: CursorContextReading {
    let context: CursorContext?

    func readContext() async throws -> CursorContext? {
        context
    }
}
