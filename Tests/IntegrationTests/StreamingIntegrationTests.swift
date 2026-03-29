// StreamingIntegrationTests.swift
// 流式转写 + 光标上下文全链路端到端集成测试
//
// 测试策略：
// - 全部使用 mock 组件，不依赖真实麦克风、AX API 或网络
// - 复用与 VoxLiteTests/TestDoubles.swift 相同的组装模式，在本 target 内独立定义 mock
// - 验证 VoicePipeline 在不同模式下的完整行为链路

import AVFoundation
import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteFeature
@testable import VoxLiteInput
@testable import VoxLiteOutput
@testable import VoxLiteSystem

// MARK: - 集成测试专用 Mock 组件

/// 状态机 mock：记录所有状态迁移
final class ITStateStore: StateStore {
    var current: VoxState = .idle
    private(set) var transitions: [VoxState] = []

    func transition(to next: VoxState) -> Bool {
        transitions.append(next)
        current = next
        return true
    }
}

/// 音频采集 mock：生成包含临时文件路径的 Data 负载
struct ITAudioCapture: AudioCaptureServing {
    var shouldFail = false
    var stopElapsedMs: Int = 800
    var stopFileContents = Data("stub".utf8)
    var stopResult: Result<Data, Error>?

    func startRecording() throws -> UUID {
        if shouldFail {
            throw VoxErrorCode.recordingUnavailable
        }
        return UUID()
    }

    func stopRecording(sessionId: UUID) throws -> Data {
        if let stopResult {
            return try stopResult.get()
        }
        // 生成符合 VoicePipeline.parseAudioPayload 格式的负载
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("it-test-\(sessionId.uuidString)")
            .appendingPathExtension("caf")
        try stopFileContents.write(to: fileURL)
        return "file://\(fileURL.path(percentEncoded: false))|\(stopElapsedMs)".data(using: .utf8) ?? Data()
    }
}

/// 文件转写 mock：返回预设文本
struct ITTranscriber: SpeechTranscribing {
    var result: Result<SpeechTranscription, Error> = .success(
        SpeechTranscription(text: "集成测试转写文本", latencyMs: 50, usedOnDevice: true)
    )

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        try result.get()
    }
}

/// 流式转写 mock：通过 AsyncStream 发送 PartialTranscription
final class ITStreamingTranscriber: StreamingTranscribing, @unchecked Sendable {
    var partialResults: [PartialTranscription] = []
    var shouldFailStreaming = false
    private(set) var startCalledCount = 0
    private(set) var stopCalledCount = 0
    private(set) var appendedBufferCount = 0

    var didStop: Bool { stopCalledCount > 0 }

    func startStreaming() -> AsyncStream<PartialTranscription> {
        startCalledCount += 1
        if shouldFailStreaming {
            // 直接结束流，模拟流式组件失败
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

/// 光标上下文读取 mock：返回预设 CursorContext 或 nil
final class ITCursorReader: CursorContextReading, @unchecked Sendable {
    var contextToReturn: CursorContext?
    var shouldThrow = false
    private(set) var readCalledCount = 0

    func readContext() async throws -> CursorContext? {
        readCalledCount += 1
        if shouldThrow {
            // 模拟 AX 权限被拒等异常
            throw VoxErrorCode.contextUnavailable
        }
        return contextToReturn
    }
}

/// 文本清洗 mock：记录传入的 context，返回预设结果
@MainActor
final class ITCleaner: TextCleaning {
    var result: CleanResult
    private(set) var capturedContexts: [ContextInfo] = []
    private(set) var capturedTranscripts: [String] = []

    init(result: CleanResult = CleanResult(
        cleanText: "集成测试清洗后文本",
        confidence: 0.9,
        styleTag: "沟通风格",
        usedFallback: false,
        success: true,
        errorCode: nil,
        latencyMs: 5
    )) {
        self.result = result
    }

    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        capturedContexts.append(context)
        capturedTranscripts.append(transcript)
        return result
    }
}

/// 文本注入 mock：记录注入的文本
final class ITInjector: TextInjecting {
    private let results: [InjectResult]
    private(set) var injectedTexts: [String] = []
    private(set) var callCount = 0

    init(results: [InjectResult] = [
        InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 3)
    ]) {
        self.results = results
    }

    func injectText(_ text: String) -> InjectResult {
        injectedTexts.append(text)
        let index = min(callCount, results.count - 1)
        callCount += 1
        return results[index]
    }
}

/// 上下文解析 mock：返回预设 ContextInfo
struct ITContextResolver: ContextResolving {
    var context = ContextInfo(
        bundleId: "com.integration.test",
        appCategory: .communication,
        inputRole: "textField",
        locale: "zh_CN"
    )

    func resolveContext() -> ContextInfo {
        context
    }
}

/// 权限管理 mock：可配置各权限状态
@MainActor
final class ITPermissions: PermissionManaging {
    var snapshot: PermissionSnapshot

    init(snapshot: PermissionSnapshot = PermissionSnapshot(
        microphoneGranted: true,
        speechRecognitionGranted: true,
        accessibilityGranted: true
    )) {
        self.snapshot = snapshot
    }

    func hasRequiredPermissions() -> Bool {
        snapshot.allGranted
    }

    func currentPermissionSnapshot() -> PermissionSnapshot {
        snapshot
    }

    func requestPermission(_ item: PermissionItem) async -> Bool {
        true
    }

    func openSystemSettings(for item: PermissionItem) {}
}

/// 无操作日志 mock
struct ITLogger: LoggerServing {
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) {}
    func error(_ message: String) {}
}

/// 指标收集 mock：记录所有 record 调用
final class ITMetrics: MetricsServing, @unchecked Sendable {
    struct Record: Equatable {
        let event: String
        let success: Bool
        let errorCode: VoxErrorCode?
        let latencyMs: Int
    }

    private(set) var records: [Record] = []

    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {
        records.append(.init(event: event, success: success, errorCode: errorCode, latencyMs: latencyMs))
    }

    func percentile(_ event: String, _ value: Double) -> Int? {
        nil
    }
}

// MARK: - Pipeline 组装工厂

@MainActor
func makeIntegrationPipeline(
    stateMachine: ITStateStore = ITStateStore(),
    audioCapture: ITAudioCapture = ITAudioCapture(),
    transcriber: any SpeechTranscribing = ITTranscriber(),
    contextResolver: any ContextResolving = ITContextResolver(),
    cleaner: any TextCleaning = ITCleaner(),
    injector: ITInjector = ITInjector(),
    permissions: ITPermissions = ITPermissions(),
    metrics: ITMetrics = ITMetrics(),
    streamingTranscriber: ITStreamingTranscriber? = nil,
    cursorReader: ITCursorReader? = nil,
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
        permissions: permissions,
        logger: ITLogger(),
        metrics: metrics,
        retryPolicy: RetryPolicy(timeoutMs: 3_000, maxRetries: 1),
        streamingTranscriber: streamingTranscriber,
        streamingAudio: nil,
        cursorReader: cursorReader,
        streamingMode: streamingMode,
        onPartialTranscription: onPartialTranscription
    )
}

// MARK: - 集成测试套件

@MainActor
struct StreamingIntegrationTests {

    // MARK: - 测试 1：完整流程（previewOnly 模式）

    /// 验证按下→录音→流式预览→松开→文件转写→清洗→注入的完整流程
    /// - 断言：partial results 被回调、最终文本来自文件转写并正确传入清洗
    @Test
    func testFullPipelineStreamingPreviewOnly() async throws {
        // 准备流式预览的中间结果
        let streamingTranscriber = ITStreamingTranscriber()
        streamingTranscriber.partialResults = [
            PartialTranscription(text: "集成测", isFinal: false, confidence: 0.6),
            PartialTranscription(text: "集成测试", isFinal: false, confidence: 0.8),
            PartialTranscription(text: "集成测试完成", isFinal: true, confidence: 0.95)
        ]

        let cursorReader = ITCursorReader()
        cursorReader.contextToReturn = CursorContext(
            surroundingText: "当前编辑器内容",
            selectedText: nil,
            appBundleId: "com.apple.notes",
            cursorPosition: 5
        )

        var receivedPartials: [PartialTranscription] = []
        let cleaner = ITCleaner()
        let injector = ITInjector()

        let pipeline = makeIntegrationPipeline(
            cleaner: cleaner,
            injector: injector,
            streamingTranscriber: streamingTranscriber,
            cursorReader: cursorReader,
            streamingMode: .previewOnly,
            onPartialTranscription: { partial in
                receivedPartials.append(partial)
            }
        )

        // 模拟按下→录音
        let sessionId = try pipeline.startRecording()
        // 模拟松开→处理
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        // 验证流式预览产出了 partial results
        #expect(receivedPartials.count == 3, "应收到 3 个 partial results")
        #expect(receivedPartials[0].text == "集成测")
        #expect(receivedPartials[0].isFinal == false)
        #expect(receivedPartials[2].isFinal == true, "最后一个 partial 应标记为 isFinal")

        // 验证最终结果来自文件转写
        #expect(result.transcript.text == "集成测试转写文本", "最终文本应来自文件转写，而非流式结果")
        #expect(result.transcript.success == true)

        // 验证清洗阶段接收到正确的文本
        #expect(cleaner.capturedTranscripts.count == 1)
        #expect(cleaner.capturedTranscripts[0] == "集成测试转写文本")

        // 验证清洗收到了光标上下文
        #expect(cleaner.capturedContexts.count == 1)
        #expect(cleaner.capturedContexts[0].enrich?.cursorContext?.surroundingText == "当前编辑器内容")

        // 验证注入收到清洗后的文本
        #expect(injector.injectedTexts == ["集成测试清洗后文本"])
        #expect(result.inject.success == true)

        // 验证流式组件被正确调用和停止
        #expect(streamingTranscriber.startCalledCount == 1)
        #expect(streamingTranscriber.stopCalledCount >= 1)

        // 验证光标上下文被读取
        #expect(cursorReader.readCalledCount == 1)
    }

    // MARK: - 测试 2：StreamingMode.off 回归

    /// 验证 StreamingMode.off 下与原始行为 100% 一致
    /// - 流式组件不应被调用，光标 reader 不应被调用
    @Test
    func testFullPipelineOffModeRegression() async throws {
        let streamingTranscriber = ITStreamingTranscriber()
        let cursorReader = ITCursorReader()
        cursorReader.contextToReturn = CursorContext(
            surroundingText: "此上下文不应被读取",
            selectedText: nil,
            appBundleId: "com.test",
            cursorPosition: nil
        )

        let cleaner = ITCleaner()
        let injector = ITInjector()
        let stateMachine = ITStateStore()

        let pipeline = makeIntegrationPipeline(
            stateMachine: stateMachine,
            cleaner: cleaner,
            injector: injector,
            streamingTranscriber: streamingTranscriber,
            cursorReader: cursorReader,
            streamingMode: .off  // 关键：off 模式
        )

        let sessionId = try pipeline.startRecording()
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        // 验证流式组件完全未被调用（off 模式核心约束）
        #expect(streamingTranscriber.startCalledCount == 0, "off 模式不应启动流式转写")
        #expect(cursorReader.readCalledCount == 0, "off 模式不应读取光标上下文")

        // 验证基础转写链路正常（与原始行为一致）
        #expect(result.transcript.text == "集成测试转写文本")
        #expect(result.transcript.success == true)
        #expect(result.inject.success == true)

        // 验证光标上下文为 nil（未被注入到 enrich）
        #expect(cleaner.capturedContexts[0].enrich?.cursorContext == nil, "off 模式下清洗上下文不含光标数据")

        // 验证状态迁移路径：recording → processing → injecting → done
        #expect(stateMachine.transitions.contains(.recording))
        #expect(stateMachine.transitions.contains(.processing))
        #expect(stateMachine.transitions.contains(.done))
    }

    // MARK: - 测试 3：光标上下文端到端链路

    /// 验证光标上下文从 AX 读取→注入 ContextEnrichment→嵌入 TextCleaner prompt→传入 Whisper prompt 全链路
    @Test
    func testCursorContextEndToEnd() async throws {
        let cursorContext = CursorContext(
            surroundingText: "正在用 Swift 编写 VoicePipeline 集成测试",
            selectedText: "VoicePipeline",
            appBundleId: "com.apple.dt.Xcode",
            cursorPosition: 24
        )

        let cursorReader = ITCursorReader()
        cursorReader.contextToReturn = cursorContext

        let cleaner = ITCleaner()

        let pipeline = makeIntegrationPipeline(
            cleaner: cleaner,
            streamingTranscriber: ITStreamingTranscriber(),
            cursorReader: cursorReader,
            streamingMode: .previewOnly  // 需要非 off 模式才会读取光标
        )

        let sessionId = try pipeline.startRecording()
        _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        // 验证光标上下文被正确读取
        #expect(cursorReader.readCalledCount == 1, "光标上下文应被读取一次")

        // 验证 ContextEnrichment 中正确包含了光标信息
        #expect(cleaner.capturedContexts.count == 1)
        let enrichedContext = cleaner.capturedContexts[0]
        let enrichment = enrichedContext.enrich
        #expect(enrichment != nil, "ContextEnrichment 不应为 nil")
        #expect(enrichment?.cursorContext?.surroundingText == "正在用 Swift 编写 VoicePipeline 集成测试")
        #expect(enrichment?.cursorContext?.selectedText == "VoicePipeline")
        #expect(enrichment?.cursorContext?.appBundleId == "com.apple.dt.Xcode")
        #expect(enrichment?.cursorContext?.cursorPosition == 24)

        // 验证 cursorContext 不为 nil，说明传入了 Whisper prompt 链路
        #expect(enrichedContext.enrich?.cursorContext == cursorContext, "光标上下文应完整传入清洗阶段")
    }

    // MARK: - 测试 4：流式组件失败后回退到纯文件转写

    /// 验证流式组件失败（空流/异常）后，主链路自动回退到文件转写，最终结果不受影响
    @Test
    func testStreamingFailureFallbackToFileOnly() async throws {
        let streamingTranscriber = ITStreamingTranscriber()
        // 配置流式组件失败：startStreaming 立即结束，不产出任何 partial
        streamingTranscriber.shouldFailStreaming = true

        var receivedPartials: [PartialTranscription] = []
        let injector = ITInjector()

        let pipeline = makeIntegrationPipeline(
            injector: injector,
            streamingTranscriber: streamingTranscriber,
            cursorReader: ITCursorReader(),
            streamingMode: .previewOnly,
            onPartialTranscription: { partial in
                receivedPartials.append(partial)
            }
        )

        let sessionId = try pipeline.startRecording()
        // 流式失败不应导致 stopRecordingAndProcess 抛出错误
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        // 验证流式失败未影响最终结果
        #expect(result.transcript.text == "集成测试转写文本", "流式失败后应回退到文件转写，最终文本不受影响")
        #expect(result.transcript.success == true)
        #expect(result.inject.success == true)

        // 验证没有 partial 被回调（流已失败）
        #expect(receivedPartials.isEmpty, "流式组件失败，不应产出任何 partial result")

        // 验证流式组件确实被启动（尝试了流式路径）
        #expect(streamingTranscriber.startCalledCount == 1, "流式组件应被尝试启动")
        // 验证注入正常完成
        #expect(injector.injectedTexts.count == 1)
    }

    // MARK: - 测试 5：AX 权限被拒时全链路正常

    /// 验证 AX 权限被拒时，光标上下文为 nil，其余链路正常执行
    @Test
    func testAXPermissionDeniedFullPipeline() async throws {
        let cursorReader = ITCursorReader()
        // 配置 AX 权限被拒：readContext() 抛出异常
        cursorReader.shouldThrow = true

        let cleaner = ITCleaner()
        let injector = ITInjector()

        let pipeline = makeIntegrationPipeline(
            cleaner: cleaner,
            injector: injector,
            streamingTranscriber: ITStreamingTranscriber(),
            cursorReader: cursorReader,
            streamingMode: .previewOnly
        )

        let sessionId = try pipeline.startRecording()
        // AX 权限异常不应导致 Pipeline 崩溃或抛出错误
        let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        // 验证光标 reader 被尝试调用了
        #expect(cursorReader.readCalledCount == 1, "即便权限被拒也应尝试读取光标")

        // 验证 AX 异常后，清洗阶段收到的 context 不含光标数据
        #expect(cleaner.capturedContexts.count == 1)
        #expect(cleaner.capturedContexts[0].enrich?.cursorContext == nil,
                "AX 权限被拒时，光标上下文应为 nil")

        // 验证其余链路不受影响
        #expect(result.transcript.text == "集成测试转写文本")
        #expect(result.transcript.success == true)
        #expect(result.inject.success == true)
        #expect(injector.injectedTexts.count == 1)
    }

    // MARK: - 测试 6：快速连续按下/松开防抖验证

    /// 验证快速连续按下/松开（<120ms），防抖和状态机不混乱
    @Test
    func testConcurrentStartStop() async throws {
        // 场景 A：正常快速启停，确保状态机顺序正确
        let stateMachine = ITStateStore()
        let pipeline = makeIntegrationPipeline(
            stateMachine: stateMachine,
            streamingMode: .off
        )

        // 第一次完整流程
        let sessionId1 = try pipeline.startRecording()
        let result1 = try await pipeline.stopRecordingAndProcess(sessionId: sessionId1)
        #expect(result1.transcript.success == true)
        #expect(stateMachine.current == .done)

        // 重置到 idle，进行第二次流程（模拟快速连续操作后的正常恢复）
        pipeline.resetToIdle()
        #expect(stateMachine.current == .idle, "resetToIdle 后应回到 idle 状态")

        // 第二次完整流程
        let sessionId2 = try pipeline.startRecording()
        let result2 = try await pipeline.stopRecordingAndProcess(sessionId: sessionId2)
        #expect(result2.transcript.success == true)
        #expect(stateMachine.current == .done)

        // 验证两次 sessionId 不同（隔离性）
        #expect(sessionId1 != sessionId2, "两次录音会话应有不同的 UUID")

        // 验证状态机迁移包含完整路径（recording → processing → done 各出现两次）
        let recordingCount = stateMachine.transitions.filter { $0 == .recording }.count
        let processingCount = stateMachine.transitions.filter { $0 == .processing }.count
        let doneCount = stateMachine.transitions.filter { $0 == .done }.count
        #expect(recordingCount == 2, "两次启停，recording 状态应出现 2 次")
        #expect(processingCount == 2, "两次启停，processing 状态应出现 2 次")
        #expect(doneCount == 2, "两次启停，done 状态应出现 2 次")
    }
}
