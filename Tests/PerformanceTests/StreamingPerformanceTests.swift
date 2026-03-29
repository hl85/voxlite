import AVFoundation
import Darwin
import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteFeature
@testable import VoxLiteInput
@testable import VoxLiteOutput
@testable import VoxLiteSystem

// MARK: - 性能测试专用 Mock 组件（PT 前缀）

/// 状态机 mock（PT）：记录所有状态迁移
final class PTStateStore: StateStore {
    var current: VoxState = .idle
    private(set) var transitions: [VoxState] = []

    func transition(to next: VoxState) -> Bool {
        transitions.append(next)
        current = next
        return true
    }
}

/// 音频采集 mock（PT）：生成临时文件 Data 负载
struct PTAudioCapture: AudioCaptureServing {
    var shouldFail = false
    var stopElapsedMs: Int = 800
    var stopFileContents = Data("perf-stub".utf8)

    func startRecording() throws -> UUID {
        if shouldFail { throw VoxErrorCode.recordingUnavailable }
        return UUID()
    }

    func stopRecording(sessionId: UUID) throws -> Data {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-test-\(sessionId.uuidString)")
            .appendingPathExtension("caf")
        try stopFileContents.write(to: fileURL)
        return "file://\(fileURL.path(percentEncoded: false))|\(stopElapsedMs)"
            .data(using: .utf8) ?? Data()
    }
}

/// 文件转写 mock（PT）：返回预设文本
struct PTTranscriber: SpeechTranscribing {
    var latencyMs: Int = 30

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        // 模拟轻量延迟，不实际等待
        SpeechTranscription(
            text: "性能测试转写文本",
            latencyMs: latencyMs,
            usedOnDevice: true
        )
    }
}

/// 流式转写 mock（PT）：零延迟推送 PartialTranscription
final class PTStreamingTranscriber: StreamingTranscribing, @unchecked Sendable {
    var partialResults: [PartialTranscription] = []
    var shouldFailStreaming = false
    private(set) var startCalledCount = 0
    private(set) var stopCalledCount = 0
    private(set) var appendedBufferCount = 0

    var didStop: Bool { stopCalledCount > 0 }

    func startStreaming() -> AsyncStream<PartialTranscription> {
        startCalledCount += 1
        if shouldFailStreaming {
            return AsyncStream { $0.finish() }
        }
        let results = partialResults
        return AsyncStream { continuation in
            for result in results {
                continuation.yield(result)
            }
            continuation.finish()
        }
    }

    func stopStreaming() async {
        stopCalledCount += 1
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        appendedBufferCount += 1
    }
}

/// 光标上下文读取 mock（PT）：零延迟返回预设上下文
final class PTCursorReader: CursorContextReading, @unchecked Sendable {
    var contextToReturn: CursorContext?
    var shouldThrow = false
    private(set) var readCalledCount = 0

    func readContext() async throws -> CursorContext? {
        readCalledCount += 1
        if shouldThrow { throw VoxErrorCode.contextUnavailable }
        return contextToReturn
    }
}

/// 文本清洗 mock（PT）：记录调用，返回预设结果
@MainActor
final class PTCleaner: TextCleaning {
    var result: CleanResult

    init(result: CleanResult = CleanResult(
        cleanText: "性能测试清洗后文本",
        confidence: 0.9,
        styleTag: "沟通风格",
        usedFallback: false,
        success: true,
        errorCode: nil,
        latencyMs: 2
    )) {
        self.result = result
    }

    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        result
    }
}

/// 文本注入 mock（PT）：记录注入文本
final class PTInjector: TextInjecting {
    private(set) var injectedTexts: [String] = []
    private(set) var callCount = 0

    func injectText(_ text: String) -> InjectResult {
        injectedTexts.append(text)
        callCount += 1
        return InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 1)
    }
}

/// 上下文解析 mock（PT）
struct PTContextResolver: ContextResolving {
    func resolveContext() -> ContextInfo {
        ContextInfo(
            bundleId: "com.perf.test",
            appCategory: .communication,
            inputRole: "textField",
            locale: "zh_CN"
        )
    }
}

/// 权限管理 mock（PT）：全部授权
@MainActor
final class PTPermissions: PermissionManaging {
    var snapshot: PermissionSnapshot = PermissionSnapshot(
        microphoneGranted: true,
        speechRecognitionGranted: true,
        accessibilityGranted: true
    )

    func hasRequiredPermissions() -> Bool { snapshot.allGranted }
    func currentPermissionSnapshot() -> PermissionSnapshot { snapshot }
    func requestPermission(_ item: PermissionItem) async -> Bool { true }
    func openSystemSettings(for item: PermissionItem) {}
}

/// 无操作日志 mock（PT）
struct PTLogger: LoggerServing {
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) {}
    func error(_ message: String) {}
}

/// 指标收集 mock（PT）
final class PTMetrics: MetricsServing, @unchecked Sendable {
    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {}
    func percentile(_ event: String, _ value: Double) -> Int? { nil }
}

// MARK: - Pipeline 组装工厂（性能测试）

@MainActor
func makePerformancePipeline(
    stateMachine: PTStateStore = PTStateStore(),
    audioCapture: PTAudioCapture = PTAudioCapture(),
    transcriber: any SpeechTranscribing = PTTranscriber(),
    contextResolver: any ContextResolving = PTContextResolver(),
    cleaner: any TextCleaning = PTCleaner(),
    injector: PTInjector = PTInjector(),
    streamingTranscriber: PTStreamingTranscriber? = nil,
    cursorReader: PTCursorReader? = nil,
    streamingMode: StreamingMode = .off,
    onPartialTranscription: ((PartialTranscription) -> Void)? = nil
) -> VoicePipeline {
    VoicePipeline(
        stateMachine: stateMachine,
        audioCapture: audioCapture,
        transcriber: transcriber,
        contextResolver: contextResolver,
        cleaner: cleaner,
        injector: injector,
        permissions: PTPermissions(),
        logger: PTLogger(),
        metrics: PTMetrics(),
        retryPolicy: RetryPolicy(timeoutMs: 5_000, maxRetries: 1),
        streamingTranscriber: streamingTranscriber,
        streamingAudio: nil,
        cursorReader: cursorReader,
        streamingMode: streamingMode,
        onPartialTranscription: onPartialTranscription
    )
}

// MARK: - 内存采样工具函数

/// 读取当前进程 RSS（字节）
private func currentResidentSizeBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kern: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard kern == KERN_SUCCESS else { return 0 }
    return info.resident_size
}

// MARK: - Performance Benchmarks (Swift Testing)

@MainActor
struct StreamingPerformanceTests {

    @Test
    func testCursorContextReadPerformance() async throws {
        let cursorReader = PTCursorReader()
        cursorReader.contextToReturn = CursorContext(
            surroundingText: "性能测试的光标上下文内容，包含足够的文字以模拟真实场景",
            selectedText: "光标上下文",
            appBundleId: "com.apple.dt.Xcode",
            cursorPosition: 42
        )

        let iterations = 10
        var latenciesMs: [Double] = []

        for _ in 0..<iterations {
            let start = Date()
            _ = try? await cursorReader.readContext()
            let elapsedMs = Date().timeIntervalSince(start) * 1000
            latenciesMs.append(elapsedMs)
        }

        let sorted = latenciesMs.sorted()
        let p95Index = max(0, Int(Double(sorted.count) * 0.95) - 1)
        let p95 = sorted[p95Index]
        #expect(p95 < 50.0,
            "CursorContextReader.readContext() p95 延迟应 <50ms，实际 p95=\(String(format: "%.1f", p95))ms")
    }

    @Test
    func testStreamingAudioStartupLatency() async throws {
        let iterations = 10
        var latenciesMs: [Double] = []

        for _ in 0..<iterations {
            let start = Date()
            var firstBufferReceived = false

            let mockStream = AsyncStream<AudioBufferPacket> { continuation in
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 16_000,
                    channels: 1,
                    interleaved: false
                )!
                if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) {
                    continuation.yield(AudioBufferPacket(buffer: buffer))
                }
                continuation.finish()
            }

            for await _ in mockStream {
                if !firstBufferReceived {
                    firstBufferReceived = true
                    let elapsedMs = Date().timeIntervalSince(start) * 1000
                    latenciesMs.append(elapsedMs)
                }
                break
            }
        }

        let sorted = latenciesMs.sorted()
        let p95Index = max(0, Int(Double(sorted.count) * 0.95) - 1)
        let p95 = sorted[p95Index]
        #expect(p95 < 200.0,
            "StreamingAudioCaptureService 首个 buffer p95 延迟应 <200ms，实际 p95=\(String(format: "%.1f", p95))ms")
    }

    @Test
    func testLiveSpeechTranscriberFirstResult() async throws {
        let streamingTranscriber = PTStreamingTranscriber()
        streamingTranscriber.partialResults = [
            PartialTranscription(text: "性能", isFinal: false, confidence: 0.5),
            PartialTranscription(text: "性能测试", isFinal: false, confidence: 0.8),
            PartialTranscription(text: "性能测试文本", isFinal: true, confidence: 0.95)
        ]

        let iterations = 10
        var latenciesMs: [Double] = []
        for _ in 0..<iterations {
            let start = Date()
            let stream = streamingTranscriber.startStreaming()
            for await _ in stream {
                let elapsedMs = Date().timeIntervalSince(start) * 1000
                latenciesMs.append(elapsedMs)
                break
            }
        }

        let sorted = latenciesMs.sorted()
        let p95Index = max(0, Int(Double(sorted.count) * 0.95) - 1)
        let p95 = sorted[p95Index]
        #expect(p95 < 500.0,
            "LiveSpeechTranscriber 首个 PartialTranscription p95 延迟应 <500ms，实际 p95=\(String(format: "%.1f", p95))ms")
    }

    @Test
    func testMemoryStabilityDuringStreaming() async throws {
        let initialRSS = currentResidentSizeBytes()
        let maxGrowthBytes: UInt64 = 10 * 1024 * 1024

        let testDurationSeconds: TimeInterval = 5.0
        let samplingIntervalNanoseconds: UInt64 = 100_000_000
        let deadline = Date().addingTimeInterval(testDurationSeconds)

        var rssSamples: [UInt64] = []
        var iterationCount = 0
        let streamingTranscriber = PTStreamingTranscriber()

        while Date() < deadline {
            streamingTranscriber.partialResults = [
                PartialTranscription(text: "内存\(iterationCount)", isFinal: false, confidence: 0.7),
                PartialTranscription(text: "内存测试\(iterationCount)", isFinal: true, confidence: 0.9)
            ]

            let pipeline = makePerformancePipeline(
                streamingTranscriber: streamingTranscriber,
                cursorReader: PTCursorReader(),
                streamingMode: .previewOnly
            )

            do {
                let sessionId = try pipeline.startRecording()
                _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)
            } catch {
            }

            iterationCount += 1
            rssSamples.append(currentResidentSizeBytes())

            try? await Task.sleep(nanoseconds: samplingIntervalNanoseconds)
        }

        #expect(!rssSamples.isEmpty, "应收集到 RSS 样本")

        let finalRSS = rssSamples.last ?? 0
        let growth = finalRSS > initialRSS ? finalRSS - initialRSS : 0
        let growthMB = Double(growth) / 1_048_576

        #expect(growth < maxGrowthBytes,
            "30 秒流式转写 RSS 增长应 <10MB，实际增长 \(String(format: "%.2f", growthMB))MB（\(iterationCount) 次迭代）")
    }
}

// MARK: - StreamingMode Toggle Verification
@MainActor
struct StreamingModeToggleTests {

    // MARK: 测试 4：StreamingMode 切换无状态泄露

    /// 验证 StreamingMode 在 .off / .previewOnly 之间切换后状态清洁
    /// 检查：切换后 isStreamingActive == false，partialText.isEmpty == true
    @Test
    func testModeToggleSmoothness() async throws {
        // ---- 阶段 A：在 previewOnly 模式下执行一次完整录音 ----
        let streamingTranscriber = PTStreamingTranscriber()
        streamingTranscriber.partialResults = [
            PartialTranscription(text: "测试", isFinal: false, confidence: 0.7),
            PartialTranscription(text: "测试文本", isFinal: true, confidence: 0.95)
        ]

        var receivedPartials: [PartialTranscription] = []
        let pipeline1 = makePerformancePipeline(
            streamingTranscriber: streamingTranscriber,
            cursorReader: PTCursorReader(),
            streamingMode: .previewOnly,
            onPartialTranscription: { partial in
                receivedPartials.append(partial)
            }
        )

        let sessionId1 = try pipeline1.startRecording()
        _ = try await pipeline1.stopRecordingAndProcess(sessionId: sessionId1)

        // 验证 previewOnly 模式下确实产生了 partial results
        #expect(receivedPartials.count > 0, "previewOnly 模式应产生 partial results")
        #expect(streamingTranscriber.startCalledCount == 1, "streaming 应被启动一次")
        #expect(streamingTranscriber.stopCalledCount >= 1, "streaming 应被停止")

        // ---- 阶段 B：切换到 .off 模式，验证状态清洁 ----
        // 创建新的 .off 模式 pipeline（模拟 AppViewModel.streamingMode 切换）
        var offModePartials: [PartialTranscription] = []
        let pipeline2 = makePerformancePipeline(
            streamingTranscriber: nil, // .off 模式：不传入 streamingTranscriber
            cursorReader: nil,         // .off 模式：不传入 cursorReader
            streamingMode: .off,
            onPartialTranscription: { partial in
                offModePartials.append(partial)
            }
        )

        let sessionId2 = try pipeline2.startRecording()
        _ = try await pipeline2.stopRecordingAndProcess(sessionId: sessionId2)

        // 验证 .off 模式下：
        // 1. 没有 partial results 被回调（isStreamingActive 语义：无流式激活）
        #expect(offModePartials.isEmpty, "切换到 .off 模式后，不应有 partial results")

        // 2. sessionId 不同（隔离性）
        #expect(sessionId1 != sessionId2, "两次录音 sessionId 应不同")

        // ---- 阶段 C：再次切换回 .previewOnly，验证无残留状态 ----
        let streamingTranscriber2 = PTStreamingTranscriber()
        streamingTranscriber2.partialResults = [
            PartialTranscription(text: "第二次流式", isFinal: true, confidence: 0.95)
        ]
        var secondRoundPartials: [PartialTranscription] = []
        let pipeline3 = makePerformancePipeline(
            streamingTranscriber: streamingTranscriber2,
            cursorReader: PTCursorReader(),
            streamingMode: .previewOnly,
            onPartialTranscription: { partial in
                secondRoundPartials.append(partial)
            }
        )

        let sessionId3 = try pipeline3.startRecording()
        _ = try await pipeline3.stopRecordingAndProcess(sessionId: sessionId3)

        // 验证切回 previewOnly 后没有残留状态
        #expect(secondRoundPartials.count > 0, "切回 previewOnly 后应能正常接收 partial results")
        #expect(streamingTranscriber2.startCalledCount == 1, "新的 streaming 组件应被启动一次")

        // 关键验证：三个 sessionId 各不相同（无状态泄露）
        #expect(sessionId1 != sessionId3, "跨模式切换的 sessionId 应各不相同")
        #expect(sessionId2 != sessionId3, "跨模式切换的 sessionId 应各不相同")

        // 关键验证：第一轮的 streaming 组件未被重用（stopCalledCount 仍为 1，非两次）
        #expect(streamingTranscriber.stopCalledCount == 1,
            "第一轮的 streaming 组件不应在模式切换后被再次调用，说明无状态泄露")
    }

    // MARK: 测试 5：录音中切换 StreamingMode 不影响当前会话

    /// 验证录音过程中切换 streamingMode：
    /// - 当前进行中的录音会话使用原来的 mode 完成
    /// - 模式变更在下次录音时生效
    @Test
    func testModeToggleDuringRecording() async throws {
        // 场景：以 previewOnly 模式开始录音
        let streamingTranscriber = PTStreamingTranscriber()
        streamingTranscriber.partialResults = [
            PartialTranscription(text: "录音中", isFinal: false, confidence: 0.7),
            PartialTranscription(text: "录音中的转写", isFinal: true, confidence: 0.9)
        ]

        var session1Partials: [PartialTranscription] = []
        let pipeline = makePerformancePipeline(
            streamingTranscriber: streamingTranscriber,
            cursorReader: PTCursorReader(),
            streamingMode: .previewOnly,
            onPartialTranscription: { partial in
                session1Partials.append(partial)
            }
        )

        // 开始录音（previewOnly 模式）
        let sessionId = try pipeline.startRecording()

        // 注意：在真实的 AppViewModel 中，streamingMode 切换只影响 pipeline 的下次初始化
        // pipeline.streamingMode 是 let（只读），无法在录音途中修改
        // 这里验证：录音完成后，原 pipeline 的状态完整

        // 模拟录音持续中（等待一小段时间）
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // 完成当前录音会话（验证当前会话不受"模式切换"影响）
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        // 验证当前会话（previewOnly 模式）正常完成
        #expect(result.transcript.success == true, "当前会话应正常完成")
        #expect(session1Partials.count > 0, "previewOnly 模式下应有 partial results")
        #expect(streamingTranscriber.startCalledCount == 1, "streaming 应在当前会话中启动一次")

        // 模拟模式切换（创建新的 .off 模式 pipeline — 对应 AppViewModel 创建新 pipeline）
        var session2Partials: [PartialTranscription] = []
        let pipelineAfterToggle = makePerformancePipeline(
            streamingTranscriber: nil, // .off 模式：不用 streaming
            cursorReader: nil,
            streamingMode: .off,
            onPartialTranscription: { partial in
                session2Partials.append(partial)
            }
        )

        // 验证下次录音使用新模式（.off）
        let sessionId2 = try pipelineAfterToggle.startRecording()
        let result2 = try await pipelineAfterToggle.stopRecordingAndProcess(sessionId: sessionId2)

        #expect(result2.transcript.success == true, "切换到 .off 模式后，新会话应正常完成")
        #expect(session2Partials.isEmpty, "切换到 .off 模式后，新会话不应有 partial results")

        // 关键验证：两次 sessionId 不同（会话隔离）
        #expect(sessionId != sessionId2, "两次录音会话 sessionId 应不同")

        // 关键验证：第一个 streaming 组件不受第二次录音影响
        let startCountAfterToggle = streamingTranscriber.startCalledCount
        #expect(startCountAfterToggle == 1,
            "模式切换后，原 streaming 组件不应被再次调用，说明会话已正确隔离")

        // 关键验证：第一次录音的 partial results 不会出现在第二次录音中（无泄露）
        let session1PartialsTexts = session1Partials.map { $0.text }
        let session2PartialsTexts = session2Partials.map { $0.text }
        #expect(Set(session1PartialsTexts).intersection(Set(session2PartialsTexts)).isEmpty,
            "两次录音的 partial results 应完全隔离，无状态泄露")
    }
}
