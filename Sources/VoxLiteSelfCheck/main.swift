import Foundation
import VoxLiteCore
import VoxLiteDomain
import VoxLiteFeature
import VoxLiteInput
import VoxLiteOutput
import VoxLiteSystem

enum SelfCheckFailure: Error {
    case failed(String)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SelfCheckFailure.failed(message)
    }
}

func runStateMachineChecks() throws {
    let sm = VoxStateMachine()
    try require(sm.current == .idle, "initial state should be idle")
    try require(sm.transition(to: .recording), "idle -> recording")
    try require(sm.transition(to: .processing), "recording -> processing")
    try require(sm.transition(to: .injecting), "processing -> injecting")
    try require(sm.transition(to: .done), "injecting -> done")
    try require(sm.transition(to: .idle), "done -> idle")
    try require(sm.transition(to: .injecting) == false, "idle -> injecting should be rejected")
}

func runCleanerChecks() throws {
    let cleaner = RuleBasedTextCleaner()
    let chatContext = ContextInfo(bundleId: "com.slack", appCategory: .communication, inputRole: "textField", locale: "zh_CN")
    let devContext = ContextInfo(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN")
    let chat = cleaner.cleanText(transcript: "今晚完成接口对齐", context: chatContext)
    let dev = cleaner.cleanText(transcript: "add fallback path", context: devContext)
    let writing = cleaner.cleanText(
        transcript: "这段内容希望更正式一些",
        context: ContextInfo(bundleId: "com.apple.Pages", appCategory: .writing, inputRole: "textField", locale: "zh_CN")
    )
    let general = cleaner.cleanText(
        transcript: "   会议纪要先这样   ",
        context: ContextInfo(bundleId: "com.apple.TextEdit", appCategory: .general, inputRole: "textField", locale: "zh_CN")
    )
    try require(chat.success, "chat clean should succeed")
    try require(chat.cleanText.hasSuffix("。"), "chat clean should end with punctuation")
    try require(dev.success, "dev clean should succeed")
    try require(dev.cleanText.contains("feat(voice):"), "dev clean should include style prefix")
    try require(writing.success, "writing clean should succeed")
    try require(writing.cleanText.hasPrefix("我们建议："), "writing clean should be formalized")
    try require(general.success, "general clean should succeed")
    try require(general.cleanText == "会议纪要先这样。", "general clean should trim and punctuate")
    let empty = cleaner.cleanText(
        transcript: "  ",
        context: ContextInfo(bundleId: "com.apple.TextEdit", appCategory: .general, inputRole: "textField", locale: "zh_CN")
    )
    try require(empty.success == false, "empty transcript should fail")
}

final class StubStateStore: StateStore {
    var current: VoxState = .idle
    func transition(to next: VoxState) -> Bool {
        current = next
        return true
    }
}

struct StubAudio: AudioCaptureServing {
    func startRecording() throws -> UUID { UUID() }
    func stopRecording(sessionId: UUID) throws -> Data {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("selfcheck-\(sessionId.uuidString)")
            .appendingPathExtension("caf")
        try Data("stub".utf8).write(to: fileURL)
        return "file://\(fileURL.path(percentEncoded: false))|1200".data(using: .utf8) ?? Data()
    }
}

struct StubTranscriber: SpeechTranscribing {
    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        SpeechTranscription(text: "原始转写文本", latencyMs: 10, usedOnDevice: true)
    }
}

struct StubTranscriberTimeout: SpeechTranscribing {
    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        SpeechTranscription(text: "超时转写", latencyMs: 3501, usedOnDevice: true)
    }
}

struct StubContextResolver: ContextResolving {
    func resolveContext() -> ContextInfo {
        ContextInfo(bundleId: "com.test", appCategory: .communication, inputRole: "textField", locale: "zh_CN")
    }
}

struct StubCleanerFail: TextCleaning {
    func cleanText(transcript: String, context: ContextInfo) -> CleanResult {
        CleanResult(
            cleanText: "",
            confidence: 0,
            styleTag: "failed",
            usedFallback: false,
            success: false,
            errorCode: .cleaningUnavailable,
            latencyMs: 5
        )
    }
}

struct StubCleanerSuccess: TextCleaning {
    func cleanText(transcript: String, context: ContextInfo) -> CleanResult {
        CleanResult(
            cleanText: transcript,
            confidence: 0.9,
            styleTag: "沟通风格",
            usedFallback: false,
            success: true,
            errorCode: nil,
            latencyMs: 5
        )
    }
}

struct StubInjector: TextInjecting {
    func injectText(_ text: String) -> InjectResult {
        InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 5)
    }
}

final class StubInjectorFailAlways: TextInjecting {
    func injectText(_ text: String) -> InjectResult {
        InjectResult(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: 5)
    }
}

final class StubInjectorFailThenSuccess: TextInjecting {
    private var attempts = 0
    func injectText(_ text: String) -> InjectResult {
        attempts += 1
        if attempts == 1 {
            return InjectResult(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: 5)
        }
        return InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 5)
    }
}

@MainActor
final class StubPermissions: PermissionManaging {
    func hasRequiredPermissions() -> Bool { true }
    func currentPermissionSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphoneGranted: true, speechRecognitionGranted: true, accessibilityGranted: true)
    }
    func requestPermission(_ item: PermissionItem) async -> Bool { true }
    func openSystemSettings(for item: PermissionItem) {}
}

struct StubLogger: LoggerServing {
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) {}
    func error(_ message: String) {}
}

final class SpyLogger: LoggerServing {
    private(set) var warnings: [String] = []
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) { warnings.append(message) }
    func error(_ message: String) {}
}

final class StubMetrics: MetricsServing {
    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {}
    func percentile(_ event: String, _ value: Double) -> Int? { nil }
}

@MainActor
final class StubPermissionsMicDenied: PermissionManaging {
    func hasRequiredPermissions() -> Bool { false }
    func currentPermissionSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphoneGranted: false, speechRecognitionGranted: true, accessibilityGranted: true)
    }
    func requestPermission(_ item: PermissionItem) async -> Bool { false }
    func openSystemSettings(for item: PermissionItem) {}
}

@MainActor
final class MutablePermissionsFlow: PermissionManaging {
    var snapshot = PermissionSnapshot(microphoneGranted: false, speechRecognitionGranted: false, accessibilityGranted: false)
    private(set) var opened: [PermissionItem] = []

    func hasRequiredPermissions() -> Bool {
        snapshot.allGranted
    }

    func currentPermissionSnapshot() -> PermissionSnapshot {
        snapshot
    }

    func requestPermission(_ item: PermissionItem) async -> Bool {
        switch item {
        case .microphone:
            snapshot = PermissionSnapshot(
                microphoneGranted: true,
                speechRecognitionGranted: snapshot.speechRecognitionGranted,
                accessibilityGranted: snapshot.accessibilityGranted
            )
        case .accessibility:
            snapshot = PermissionSnapshot(
                microphoneGranted: snapshot.microphoneGranted,
                speechRecognitionGranted: snapshot.speechRecognitionGranted,
                accessibilityGranted: true
            )
        case .speechRecognition:
            snapshot = PermissionSnapshot(
                microphoneGranted: snapshot.microphoneGranted,
                speechRecognitionGranted: true,
                accessibilityGranted: snapshot.accessibilityGranted
            )
        }
        return true
    }

    func openSystemSettings(for item: PermissionItem) {
        opened.append(item)
    }
}

@MainActor
func runPipelineFallbackChecks() async throws {
    let pipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerFail(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics()
    )
    let sessionId = try pipeline.startRecording()
    let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)
    try require(result.clean.usedFallback, "clean result should fallback to transcript")
    try require(result.clean.cleanText == "原始转写文本", "fallback should preserve transcript")
}

@MainActor
func runPermissionErrorChecks() async throws {
    let pipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerFail(),
        injector: StubInjector(),
        permissions: StubPermissionsMicDenied(),
        logger: StubLogger(),
        metrics: StubMetrics()
    )
    do {
        _ = try pipeline.startRecording()
        try require(false, "permission denied should throw")
    } catch let error as VoxErrorCode {
        try require(error == .permissionMicrophoneDenied, "should map microphone permission error")
    }
}

@MainActor
func runRetryChecks() async throws {
    let recoverable = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerFail(),
        injector: StubInjectorFailThenSuccess(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: RetryPolicy(timeoutMs: 3000, maxRetries: 1)
    )
    let recoverableSession = try recoverable.startRecording()
    let recoverableResult = try await recoverable.stopRecordingAndProcess(sessionId: recoverableSession)
    try require(recoverableResult.inject.success, "retry should recover transient injection failure")

    let exhausted = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerFail(),
        injector: StubInjectorFailAlways(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: RetryPolicy(timeoutMs: 3000, maxRetries: 1)
    )
    let exhaustedSession = try exhausted.startRecording()
    do {
        _ = try await exhausted.stopRecordingAndProcess(sessionId: exhaustedSession)
        try require(false, "retry exhausted should throw")
    } catch let error as VoxErrorCode {
        try require(error == .retryExhausted, "should throw retryExhausted when retries are used up")
    }
}

@MainActor
func runTimeoutChecks() async throws {
    let timeoutPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriberTimeout(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerFail(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: RetryPolicy(timeoutMs: 3000, maxRetries: 0)
    )
    let sessionId = try timeoutPipeline.startRecording()
    do {
        _ = try await timeoutPipeline.stopRecordingAndProcess(sessionId: sessionId)
        try require(false, "timeout pipeline should throw timeout")
    } catch let error as VoxErrorCode {
        try require(error == .timeout, "timeout in stage should report timeout")
    }
}

func runFnMonitorChecks() throws {
    final class CounterBox: @unchecked Sendable {
        var pressedCount = 0
        var releasedCount = 0
    }
    let counters = CounterBox()
    let monitor = HotKeyMonitor(
        onPress: { counters.pressedCount += 1 },
        onRelease: { counters.releasedCount += 1 }
    )
    monitor.simulateFnKeyPress()
    monitor.simulateFnKeyPress()
    monitor.simulateFnKeyRelease()
    monitor.simulateFnKeyRelease()
    try require(counters.pressedCount == 1, "fn press should trigger once before release")
    try require(counters.releasedCount == 1, "fn release should trigger once after press")
}

func runClipboardInjectorChecks() throws {
    final class FakeClipboard: @unchecked Sendable {
        var text: String? = "old-value"
    }
    let clipboard = FakeClipboard()
    let logger = SpyLogger()

    let successInjector = ClipboardTextInjector(
        logger: logger,
        restoreDelayNanos: 0,
        getClipboardString: { clipboard.text },
        clearClipboard: { clipboard.text = nil },
        setClipboardString: { clipboard.text = $0 },
        pasteCommand: { true },
        scheduleRestore: { _, action in action() }
    )
    let success = successInjector.injectText("new-value")
    try require(success.success, "clipboard inject success path should succeed")
    try require(success.usedClipboardFallback == false, "success path should not mark fallback")
    try require(clipboard.text == "old-value", "success path should restore original clipboard")

    let fallbackInjector = ClipboardTextInjector(
        logger: logger,
        restoreDelayNanos: 0,
        getClipboardString: { clipboard.text },
        clearClipboard: { clipboard.text = nil },
        setClipboardString: { clipboard.text = $0 },
        pasteCommand: { false },
        scheduleRestore: { _, action in action() }
    )
    let fallback = fallbackInjector.injectText("fallback-text")
    try require(fallback.success == false, "fallback path should report failure")
    try require(fallback.usedClipboardFallback, "fallback path should mark clipboard fallback")
    try require(clipboard.text == "fallback-text", "fallback path should keep result in clipboard for manual paste")
    try require(logger.warnings.isEmpty == false, "fallback path should write warning log")
}

@MainActor
func runAppStateMachineChecks() async throws {
    let onboardingPermissions = MutablePermissionsFlow()
    let onboardingPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSuccess(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics()
    )
    let onboardingVM = AppViewModel(
        pipeline: onboardingPipeline,
        permissions: onboardingPermissions,
        performanceSampler: PerformanceSampler()
    )
    try require(onboardingVM.showOnboarding, "onboarding should show when permissions missing")
    try require(onboardingVM.onboardingStep == 1, "onboarding should start from microphone step")
    await onboardingVM.requestPermission(.microphone)
    try require(onboardingVM.onboardingStep == 2, "after microphone should move to accessibility step")
    await onboardingVM.requestPermission(.accessibility)
    try require(onboardingVM.onboardingStep == 3, "after accessibility should move to speech step")
    await onboardingVM.requestPermission(.speechRecognition)
    try require(onboardingVM.showOnboarding == false, "onboarding should close when all permissions granted")

    let denyPermissions = StubPermissionsMicDenied()
    let denyPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSuccess(),
        injector: StubInjector(),
        permissions: denyPermissions,
        logger: StubLogger(),
        metrics: StubMetrics()
    )
    let denyVM = AppViewModel(
        pipeline: denyPipeline,
        permissions: denyPermissions,
        performanceSampler: PerformanceSampler()
    )
    await denyVM.simulatePressForTesting()
    try require(denyVM.stateText == "Failed", "press with missing permission should fail")
    try require(denyVM.actionTitle == "打开系统设置", "missing permission should expose settings CTA")
    try require(denyVM.recommendedSettingItem == .microphone, "missing permission should recommend microphone settings")

    let timeoutPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriberTimeout(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSuccess(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: RetryPolicy(timeoutMs: 3000, maxRetries: 0)
    )
    let timeoutVM = AppViewModel(
        pipeline: timeoutPipeline,
        permissions: StubPermissions(),
        performanceSampler: PerformanceSampler()
    )
    await timeoutVM.simulatePressForTesting()
    await timeoutVM.simulateReleaseForTesting()
    try require(timeoutVM.canRetry, "timeout failure should allow retry")
    try require(timeoutVM.actionTitle == "重试本次", "timeout failure should show retry CTA")
    await timeoutVM.retryLatest()
    try require(timeoutVM.stateText == "Idle", "retry action should reset to idle")
    try require(timeoutVM.canRetry == false, "retry action should clear retry flag")
}

@MainActor
func runPerformanceThresholdChecks() async throws {
    let metrics = InMemoryMetrics()
    let pipeline = VoicePipeline(
        stateMachine: VoxStateMachine(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSuccess(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: metrics
    )
    for _ in 0..<20 {
        let sessionId = try pipeline.startRecording()
        _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)
        pipeline.resetToIdle()
    }
    let p50 = pipeline.percentileLatency(0.5) ?? Int.max
    let p95 = pipeline.percentileLatency(0.95) ?? Int.max
    try require(p50 < 1000, "P50 latency should be below 1000ms")
    try require(p95 < 1800, "P95 latency should be below 1800ms")
}

Task {
    do {
        try runStateMachineChecks()
        try runCleanerChecks()
        try await runPipelineFallbackChecks()
        try await runPermissionErrorChecks()
        try await runRetryChecks()
        try await runTimeoutChecks()
        try runFnMonitorChecks()
        try runClipboardInjectorChecks()
        try await runAppStateMachineChecks()
        try await runPerformanceThresholdChecks()
        print("SELF_CHECK_OK")
        exit(0)
    } catch let SelfCheckFailure.failed(message) {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    } catch {
        fputs("FAILED: \(error)\n", stderr)
        exit(1)
    }
}

dispatchMain()
