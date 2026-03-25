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

func runHotKeyDisplayStringChecks() throws {
    let fnOnly = HotKeyConfiguration.defaultConfiguration
    try require(fnOnly.displayString == "Fn", "default Fn-only config should display 'Fn'")

    let cmdOptS = HotKeyConfiguration(
        keyCode: 1, // kVK_ANSI_S
        modifiers: HotKeyConfiguration.commandModifierMask | HotKeyConfiguration.optionModifierMask
    )
    try require(cmdOptS.displayString == "⌥⌘S", "Cmd+Opt+S should display '⌥⌘S'")

    let shiftCtrlA = HotKeyConfiguration(
        keyCode: 0, // kVK_ANSI_A
        modifiers: HotKeyConfiguration.shiftModifierMask | HotKeyConfiguration.controlModifierMask
    )
    try require(shiftCtrlA.displayString == "^⇧A", "Ctrl+Shift+A should display '^⇧A'")
}

func runCleaningModeCodecChecks() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(CleaningMode.llmWithFallback)
    let decoded = try decoder.decode(CleaningMode.self, from: data)
    try require(decoded == .llmWithFallback, "cleaning mode should round-trip through JSON")
}

func runErrorDetailChecks() throws {
    let detail = ErrorDetail(
        summary: "识别超时",
        detail: "长错误描述...",
        errorCode: "TIMEOUT",
        recommendedAction: .goToSettings(.speechRecognition)
    )
    try require(detail.summary == "识别超时", "error summary should be preserved")
    try require(detail.detail == "长错误描述...", "error detail should be preserved")
    try require(detail.errorCode == "TIMEOUT", "error code should be preserved")
    try require(detail.recommendedAction == .goToSettings(.speechRecognition), "recommended action should be preserved")
}

func runAppSettingsOnboardingChecks() throws {
    var settings = AppSettings(
        hotKeyDescription: "Fn",
        launchAtLoginEnabled: false,
        menuBarDisplayMode: .iconAndSummary,
        showRecentSummary: true,
        summaryMaxLength: 48,
        historyLimit: 50,
        speechModel: ModelSetting(localEnabled: true, remoteProvider: "", remoteEndpoint: ""),
        llmModel: ModelSetting(localEnabled: true, remoteProvider: "", remoteEndpoint: "")
    )
    try require(settings.onboardingCompleted == false, "onboarding should default to false")
    settings.onboardingCompleted = true
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    try require(decoded.onboardingCompleted, "onboarding flag should persist through JSON")
}

@MainActor
func runCleanerChecks() async throws {
    let cleaner = RuleBasedTextCleaner(generator: StubPromptGenerator())
    let chatContext = ContextInfo(bundleId: "com.slack", appCategory: .communication, inputRole: "textField", locale: "zh_CN")
    let devContext = ContextInfo(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN")
    let chat = await cleaner.cleanText(transcript: "今晚完成接口对齐", context: chatContext)
    let dev = await cleaner.cleanText(transcript: "add fallback path", context: devContext)
    let writing = await cleaner.cleanText(
        transcript: "这段内容希望更正式一些",
        context: ContextInfo(bundleId: "com.apple.Pages", appCategory: .writing, inputRole: "textField", locale: "zh_CN")
    )
    let general = await cleaner.cleanText(
        transcript: "   会议纪要先这样   ",
        context: ContextInfo(bundleId: "com.apple.TextEdit", appCategory: .general, inputRole: "textField", locale: "zh_CN")
    )
    try require(chat.success, "chat clean should succeed")
    try require(chat.cleanText.contains("今晚完成接口对齐"), "chat clean should keep original meaning")
    try require(chat.cleanText.contains("原始文本：") == false, "chat clean should not output prompt text")
    try require(dev.success, "dev clean should succeed")
    try require(dev.cleanText.contains("add fallback path"), "dev clean should keep command content")
    try require(writing.success, "writing clean should succeed")
    try require(writing.cleanText.contains("更正式一些"), "writing clean should keep source content")
    try require(general.success, "general clean should succeed")
    try require(general.cleanText.contains("会议纪要先这样"), "general clean should trim and preserve source")
    let empty = await cleaner.cleanText(
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
    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
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
    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
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

struct StubPromptGenerator: PromptGenerating {
    func generateText(from prompt: String) async throws -> String {
        let markers = ["原始文本：", "用户指令：", "原始内容："]
        for marker in markers {
            if let range = prompt.range(of: marker, options: .backwards) {
                let source = prompt[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                return "加工结果：\(source)"
            }
        }
        return "加工结果：\(prompt)"
    }

    func availabilityState() -> FoundationModelAvailabilityState {
        .available
    }
}

final class CapturingPromptGenerator: PromptGenerating {
    private(set) var prompts: [String] = []
    private let output: String

    init(output: String) {
        self.output = output
    }

    func generateText(from prompt: String) async throws -> String {
        prompts.append(prompt)
        return output
    }

    func availabilityState() -> FoundationModelAvailabilityState {
        .available
    }
}

final class CapturingInjector: TextInjecting {
    private(set) var lastText: String = ""

    func injectText(_ text: String) -> InjectResult {
        lastText = text
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

final class InMemoryHistoryStore: HistoryStore {
    var items: [TranscriptHistoryItem] = []
    func loadHistory() -> [TranscriptHistoryItem] { items }
    func saveHistory(_ items: [TranscriptHistoryItem]) { self.items = items }
}

final class InMemorySkillStore: SkillStore {
    var snapshot: SkillConfigSnapshot
    init(snapshot: SkillConfigSnapshot = FileSkillStore.defaultSnapshot) {
        self.snapshot = snapshot
    }
    func loadSkills() -> SkillConfigSnapshot { snapshot }
    func saveSkills(_ snapshot: SkillConfigSnapshot) { self.snapshot = snapshot }
}

final class InMemorySettingsStore: AppSettingsStore {
    var settings: AppSettings
    init(settings: AppSettings = FileAppSettingsStore.defaultSettings) {
        self.settings = settings
    }
    func loadSettings() -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) { self.settings = settings }
}

final class StubLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var latest: Bool = false
    func setEnabled(_ enabled: Bool) { latest = enabled }
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
func runPromptToLLMInjectionChecks() async throws {
    let generator = CapturingPromptGenerator(output: "LLM加工后的结果。")
    let cleaner = RuleBasedTextCleaner(
        skillStore: InMemorySkillStore(),
        matcher: SkillMatcher(),
        generator: generator
    )
    let injector = CapturingInjector()
    let pipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: cleaner,
        injector: injector,
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics()
    )
    let sessionId = try pipeline.startRecording()
    let result = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)
    try require(generator.prompts.count == 1, "pipeline should call llm once")
    try require(generator.prompts.first?.contains("原始文本：原始转写文本") == true, "llm prompt should contain template and transcript")
    try require(injector.lastText == "LLM加工后的结果。", "injector should receive llm output instead of prompt")
    try require(result.clean.cleanText == "LLM加工后的结果。", "process result should store llm output text")
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

@MainActor
func runPrototypeMigrationChecks() async throws {
    let matcher = SkillMatcher()
    let matching = SkillMatchingConfig(
        bundleSkillMap: ["com.apple.dt.Xcode": "prompt"],
        categorySkillMap: [.development: "xiaohongshu", .general: "transcribe"],
        defaultSkillId: "transcribe"
    )
    let id1 = matcher.resolveSkillId(bundleId: "com.apple.dt.Xcode", category: .development, matching: matching)
    let id2 = matcher.resolveSkillId(bundleId: "com.unknown.app", category: .development, matching: matching)
    let id3 = matcher.resolveSkillId(bundleId: "com.unknown.app", category: .communication, matching: matching)
    try require(id1 == "prompt", "bundle 精确匹配应优先")
    try require(id2 == "xiaohongshu", "类别匹配应作为第二优先级")
    try require(id3 == "transcribe", "默认技能应兜底")

    var cleanerSnapshot = FileSkillStore.defaultSnapshot
    cleanerSnapshot.matching.bundleSkillMap = [:]
    cleanerSnapshot.matching.categorySkillMap = [:]
    cleanerSnapshot.matching.defaultSkillId = "xiaohongshu"
    let cleanerStore = InMemorySkillStore(snapshot: cleanerSnapshot)
    let cleaner = RuleBasedTextCleaner(skillStore: cleanerStore, matcher: SkillMatcher(), generator: StubPromptGenerator())
    let context = ContextInfo(bundleId: "com.unknown.app", appCategory: .general, inputRole: "field", locale: "zh-CN")
    let articleResult = await cleaner.cleanText(transcript: "今天完成接口联调", context: context)
    try require(articleResult.styleTag == "小红书文案", "默认技能应驱动清洗风格")
    try require(articleResult.cleanText.contains("今天完成接口联调"), "小红书模板应驱动 llm 处理原始内容")

    cleanerSnapshot.matching.defaultSkillId = "prompt"
    cleanerStore.saveSkills(cleanerSnapshot)
    let promptResult = await cleaner.cleanText(transcript: "新增重试链路", context: context)
    try require(promptResult.styleTag == "提示词", "切换默认技能后应命中新风格")
    try require(promptResult.cleanText.contains("新增重试链路"), "提示词模板应驱动 llm 处理用户指令")

    let historyStore = InMemoryHistoryStore()
    let skillStore = InMemorySkillStore()
    var setting = FileAppSettingsStore.defaultSettings
    setting.historyLimit = 2
    let settingsStore = InMemorySettingsStore(settings: setting)
    let launchManager = StubLaunchAtLoginManager()

    let vm = AppViewModel(
        pipeline: VoicePipeline(
            stateMachine: StubStateStore(),
            audioCapture: StubAudio(),
            transcriber: StubTranscriber(),
            contextResolver: StubContextResolver(),
            cleaner: StubCleanerSuccess(),
            injector: StubInjector(),
            permissions: StubPermissions(),
            logger: StubLogger(),
            metrics: StubMetrics()
        ),
        permissions: StubPermissions(),
        performanceSampler: PerformanceSampler(),
        historyStore: historyStore,
        skillStore: skillStore,
        settingsStore: settingsStore,
        launchAtLoginManager: launchManager
    )
    vm.skipOnboarding()
    for _ in 0..<3 {
        await vm.simulatePressForTesting()
        await vm.simulateReleaseForTesting()
    }
    try require(vm.historyItems.count == 2, "历史记录应按上限截断")
    try require(historyStore.items.count == 2, "历史记录应持久化到本地存储实现")

    try require(vm.deleteSkill("transcribe") == false, "预装技能不能删除")
    vm.setDefaultSkill("xiaohongshu")
    try require(vm.skillSnapshot.matching.defaultSkillId == "xiaohongshu", "默认技能应可切换")
    try require(vm.skillSnapshot.matching.categorySkillMap[.general] == "xiaohongshu", "切换默认技能时应同步通用类别映射")
    vm.addCustomSkill(name: "测试技能", template: "{{text}}", styleHint: "测试")
    let customId = vm.skillSnapshot.profiles.first(where: { $0.type == .custom })?.id ?? ""
    try require(customId.isEmpty == false, "应能新增自定义技能")
    try require(vm.deleteSkill(customId), "应能删除自定义技能")

    vm.setLaunchAtLogin(true)
    try require(launchManager.latest, "应将开机启动设置写入系统管理器")
    vm.setMenuBarSummaryVisible(false)
    try require(vm.menuBarSummary.isEmpty, "关闭菜单栏摘要后应清空摘要")
}

Task {
    do {
        try runStateMachineChecks()
        try runHotKeyDisplayStringChecks()
        try runCleaningModeCodecChecks()
        try runErrorDetailChecks()
        try runAppSettingsOnboardingChecks()
        try await runCleanerChecks()
        try await runPromptToLLMInjectionChecks()
        try await runPipelineFallbackChecks()
        try await runPermissionErrorChecks()
        try await runRetryChecks()
        try await runTimeoutChecks()
        try runFnMonitorChecks()
        try runClipboardInjectorChecks()
        try await runAppStateMachineChecks()
        try await runPerformanceThresholdChecks()
        try await runPrototypeMigrationChecks()
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
