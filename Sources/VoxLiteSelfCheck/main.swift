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

struct CheckResult {
    let name: String
    let passed: Bool
    let error: String?

    init(name: String, passed: Bool, error: String? = nil) {
        self.name = name
        self.passed = passed
        self.error = error
    }
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

func runKeyCodeToStringRegressionChecks() throws {
    func keyString(for keyCode: UInt16) -> String {
        KeyCodeConverter.string(for: keyCode)
    }

    let knownKeyCodes: [(UInt16, String)] = [
        (0x00, "A"),
        (0x01, "S"),
        (0x0C, "Q"),
        (0x12, "1"),
        (0x1D, "0"),
        (0x31, "Space"),
        (0x33, "Delete"),
        (0x35, "Escape"),
        (0x3F, "Fn"),
    ]
    for (keyCode, expected) in knownKeyCodes {
        let result = keyString(for: keyCode)
        try require(result == expected, "KeyCodeConverter.string(for: 0x\(String(keyCode, radix: 16))) should return \"\(expected)\", got \"\(result)\"")
    }

    let previouslyMissingKeyCodes: [(UInt16, String)] = [
        (0x6E, "▤"),
        (0x6A, "F16"),
        (0x3C, "⇧"),
        (0x73, "Home"),
        (0x77, "End"),
        (0x74, "PageUp"),
        (0x79, "PageDown"),
        (0x75, "⌦"),
        (0x72, "Help"),
    ]
    for (keyCode, expected) in previouslyMissingKeyCodes {
        let result = keyString(for: keyCode)
        try require(result == expected, "KeyCodeConverter.string(for: 0x\(String(keyCode, radix: 16))) should return \"\(expected)\", got \"\(result)\"")
    }

    let unknownKeyCode: UInt16 = 9999
    let unknownResult = keyString(for: unknownKeyCode)
    try require(unknownResult == "Key 9999", "KeyCodeConverter.string(for: 9999) should return \"Key 9999\", got \"\(unknownResult)\"")
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
        speechModel: ModelSetting(),
        llmModel: ModelSetting()
    )
    try require(settings.onboardingCompleted == false, "onboarding should default to false")
    settings.onboardingCompleted = true
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    try require(decoded.onboardingCompleted, "onboarding flag should persist through JSON")
}

func runContextInfoEnrichmentChecks() throws {
    let legacy = ContextInfo(bundleId: "com.test.legacy", appCategory: .general, inputRole: "textField", locale: "zh_CN")
    try require(legacy.bundleId == "com.test.legacy", "legacy context should preserve bundleId")
    try require(legacy.appCategory == .general, "legacy context should preserve appCategory")
    try require(legacy.enrich == nil, "legacy context init should keep enrich optional")

    let enriched = ContextInfo(
        bundleId: "com.apple.dt.Xcode",
        appCategory: .development,
        inputRole: "textField",
        locale: "zh_CN",
        enrich: ContextEnrichment(
            appName: "Xcode",
            isEditable: true,
            focusedRole: "sourceEditor",
            vocabularyBias: ["cmd": "command"]
        )
    )
    try require(enriched.enrich?.appName == "Xcode", "enriched context should preserve appName")
    try require(enriched.enrich?.focusedRole == "sourceEditor", "enriched context should preserve focusedRole")
    try require(enriched.enrich?.vocabularyBias["cmd"] == "command", "enriched context should preserve vocabulary bias")
}

@MainActor
func runCleanerChecks() async throws {
    let cleaner = RuleBasedTextCleaner(generator: FailingPromptGenerator())
    let chatContext = ContextInfo(bundleId: "com.slack", appCategory: .communication, inputRole: "textField", locale: "zh_CN")
    let devContext = ContextInfo(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN")
    let chat = await cleaner.cleanText(transcript: "今晚完成接口对齐", context: chatContext)
    let chatVerbose = await cleaner.cleanText(transcript: "嗯 今晚先和产品对齐 然后 晚点发你确认", context: chatContext)
    let dev = await cleaner.cleanText(transcript: "添加 fallbackPath 修改 user_name 删除 oldEndpoint", context: devContext)
    let writing = await cleaner.cleanText(
        transcript: "嗯 我觉得这段内容有点口语化，我们先这样，后面再想一下怎么展开",
        context: ContextInfo(bundleId: "com.apple.Pages", appCategory: .writing, inputRole: "textField", locale: "zh_CN")
    )
    let general = await cleaner.cleanText(
        transcript: "   会议纪要先这样   ",
        context: ContextInfo(bundleId: "com.apple.TextEdit", appCategory: .general, inputRole: "textField", locale: "zh_CN")
    )
    try require(chat.success, "chat clean should succeed")
    try require(chat.cleanText.contains("今晚完成接口对齐"), "chat clean should keep original meaning")
    try require(chat.cleanText == "今晚完成接口对齐。", "chat fallback should normalize sentence ending")
    try require(chatVerbose.cleanText == "今晚先和产品对齐，晚点发你确认。", "chat fallback should remove filler words and improve sentence breaks")
    try require(dev.success, "dev clean should succeed")
    try require(dev.cleanText.contains("fallbackPath"), "dev clean should keep camelCase naming")
    try require(dev.cleanText.contains("user_name"), "dev clean should keep snake_case naming")
    try require(dev.cleanText.contains("删除"), "dev clean should keep imperative tone")
    try require(writing.success, "writing clean should succeed")
    try require(writing.cleanText.contains("我认为"), "writing clean should use formal wording")
    try require(writing.cleanText.contains("\n\n"), "writing clean should promote paragraph structure")
    try require(general.success, "general clean should succeed")
    try require(general.cleanText.contains("会议纪要先这样"), "general clean should trim and preserve source")
    let empty = await cleaner.cleanText(
        transcript: "  ",
        context: ContextInfo(bundleId: "com.apple.TextEdit", appCategory: .general, inputRole: "textField", locale: "zh_CN")
    )
    try require(empty.success == false, "empty transcript should fail")

    let nonEditable = await cleaner.cleanText(
        transcript: "cmd 换成 cmd",
        context: ContextInfo(
            bundleId: "com.apple.finder",
            appCategory: .general,
            inputRole: "textField",
            locale: "zh_CN",
            enrich: ContextEnrichment(appName: "Finder", isEditable: false, focusedRole: "list", vocabularyBias: ["cmd": "command"])
        )
    )
    try require(nonEditable.cleanText.contains("command"), "non-editable context should still apply vocabulary bias")
    try require(nonEditable.cleanText.contains("。") == false, "non-editable context should soften sentence punctuation")
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

struct StubTranscriberWithLatency: SpeechTranscribing {
    let latencyMs: Int
    let text: String

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        SpeechTranscription(text: text, latencyMs: latencyMs, usedOnDevice: false)
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

struct StubCleanerSlowSuccess: TextCleaning {
    let latencyMs: Int

    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        CleanResult(
            cleanText: "远端加工：\(transcript)",
            confidence: 0.92,
            styleTag: "远端清洗",
            usedFallback: false,
            success: true,
            errorCode: nil,
            latencyMs: latencyMs
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
final class CountingStubTranscriber: SpeechTranscribing {
    private let delayNs: UInt64
    private(set) var callCount = 0

    init(delayNs: UInt64 = 0) {
        self.delayNs = delayNs
    }

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        callCount += 1
        if delayNs > 0 {
            try? await Task.sleep(nanoseconds: delayNs)
        }
        return SpeechTranscription(text: "原始转写文本", latencyMs: 5, usedOnDevice: true)
    }
}

@MainActor
final class CountingStubCleaner: TextCleaning {
    private let delayNs: UInt64
    private(set) var callCount = 0

    init(delayNs: UInt64 = 0) {
        self.delayNs = delayNs
    }

    func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        callCount += 1
        if delayNs > 0 {
            try? await Task.sleep(nanoseconds: delayNs)
        }
        return CleanResult(
            cleanText: "清洗后文本",
            confidence: 0.9,
            styleTag: "沟通风格",
            usedFallback: false,
            success: true,
            errorCode: nil,
            latencyMs: 5
        )
    }
}

final class CountingStubInjector: TextInjecting {
    private let results: [InjectResult]
    private(set) var injectedTexts: [String] = []
    private(set) var callCount = 0

    init(results: [InjectResult]) {
        self.results = results
    }

    func injectText(_ text: String) -> InjectResult {
        injectedTexts.append(text)
        let index = min(callCount, results.count - 1)
        callCount += 1
        return results[index]
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

struct FailingPromptGenerator: PromptGenerating {
    func generateText(from prompt: String) async throws -> String {
        throw PromptGenerationError.unavailable
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

final class SpyLogger: LoggerServing, @unchecked Sendable {
    private(set) var warnings: [String] = []
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func warn(_ message: String) { warnings.append(message) }
    func error(_ message: String) {}
}

final class StubMetrics: MetricsServing, Sendable {
    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {}
    func percentile(_ event: String, _ value: Double) -> Int? { nil }
}

final class SelfCheckMetrics: MetricsServing, @unchecked Sendable {
    private(set) var events: [String] = []

    func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {
        events.append(event)
    }

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

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func store(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    func retrieve(forKey key: String) throws -> String? {
        values[key]
    }

    func delete(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
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
    try require(generator.prompts.first?.contains("沟通路由补充要求") == true, "llm prompt should prepend communication route instructions")
    try require(generator.prompts.first?.contains("原始文本：原始转写文本。") == true, "llm prompt should contain normalized transcript")
    try require(injector.lastText == "LLM加工后的结果。", "injector should receive llm output instead of prompt")
    try require(result.clean.cleanText == "LLM加工后的结果。", "process result should store llm output text")
}

@MainActor
func runContextAwarePromptChecks() async throws {
    let generator = CapturingPromptGenerator(output: "command add fallback path。")
    let cleaner = RuleBasedTextCleaner(
        skillStore: InMemorySkillStore(),
        matcher: SkillMatcher(),
        generator: generator
    )
    let context = ContextInfo(
        bundleId: "com.apple.dt.Xcode",
        appCategory: .development,
        inputRole: "textField",
        locale: "zh_CN",
        enrich: ContextEnrichment(
            appName: "Xcode",
            isEditable: true,
            focusedRole: "sourceEditor",
            vocabularyBias: ["cmd": "command"]
        )
    )
    _ = await cleaner.cleanText(transcript: "cmd add fallback path", context: context)
    let prompt = generator.prompts.first ?? ""
    try require(prompt.contains("当前应用：Xcode。"), "context-aware prompt should include app name")
    try require(prompt.contains("焦点角色：sourceEditor。"), "context-aware prompt should include focused role")
    try require(prompt.contains("词汇偏置：优先使用以下写法：cmd→command。"), "context-aware prompt should include vocabulary bias")
    try require(prompt.contains("command add fallback path"), "prompt input should apply vocabulary bias before sending to llm")
}

@MainActor
func runBootstrapRemoteRuntimeChecks() throws {
    var settings = FileAppSettingsStore.defaultSettings
    settings.onboardingCompleted = true
    settings.llmModel = ModelSetting(
        useRemote: true,
        provider: .deepseek,
        customEndpoint: "",
        selectedSTTModel: "",
        selectedLLMModel: "deepseek-chat"
    )

    let settingsStore = InMemorySettingsStore(settings: settings)
    let keychain = InMemoryKeychainStore(values: [RemoteProvider.deepseek.rawValue: "deepseek-test-key"])
    let skillStore = InMemorySkillStore()
    let historyStore = InMemoryHistoryStore()

    let vm = VoxLiteFeatureBootstrap.makeDefaultViewModel(
        historyStore: historyStore,
        skillStore: skillStore,
        settingsStore: settingsStore,
        launchAtLoginManager: StubLaunchAtLoginManager(),
        keychain: keychain,
        permissions: StubPermissions(),
        performanceSampler: PerformanceSampler()
    )

    try require(vm.llmModelName == "Deepseek 深度求索 (deepseek-chat)", "bootstrap should use persisted remote llm settings for runtime model name")
    try require(vm.foundationModelAvailability == .available, "runtime availability should come from active cleaner/generator chain")
    try require(vm.foundationModelStatus == "已就绪", "runtime status should reflect active remote generator availability")
    try require(vm.foundationModelReadiness == .ready, "runtime readiness enum should reflect active remote generator availability")
}

@MainActor
func runHotSwitchRuntimeChecks() throws {
    let skillStore = InMemorySkillStore()
    let historyStore = InMemoryHistoryStore()
    let keychain = InMemoryKeychainStore(values: [RemoteProvider.deepseek.rawValue: "deepseek-test-key"])
    var initialSettings = FileAppSettingsStore.defaultSettings
    initialSettings.onboardingCompleted = true
    let settingsStore = InMemorySettingsStore(settings: initialSettings)

    let vm = VoxLiteFeatureBootstrap.makeDefaultViewModel(
        historyStore: historyStore,
        skillStore: skillStore,
        settingsStore: settingsStore,
        launchAtLoginManager: StubLaunchAtLoginManager(),
        keychain: keychain,
        permissions: StubPermissions(),
        performanceSampler: PerformanceSampler()
    )

    try require(vm.llmModelName == "Apple Foundation Model", "default runtime should start with local llm")

    vm.appSettings.llmModel = ModelSetting(
        useRemote: true,
        provider: .deepseek,
        customEndpoint: "",
        selectedSTTModel: "",
        selectedLLMModel: "deepseek-chat"
    )

    let switched = vm.saveRemoteModelSettings()
    try require(switched, "idle runtime should hot-switch successfully after saving settings")
    try require(vm.llmModelName == "Deepseek 深度求索 (deepseek-chat)", "hot-switch should refresh active llm model name immediately")
    try require(vm.foundationModelAvailability == .available, "hot-switch should refresh active availability immediately")
    try require(vm.foundationModelStatus == "已就绪", "hot-switch should refresh active model status immediately")
    try require(vm.foundationModelReadiness == .ready, "hot-switch should refresh active readiness enum immediately")
}

@MainActor
func runFallbackMessageChecks() async throws {
    let settingsStore = InMemorySettingsStore(settings: FileAppSettingsStore.defaultSettings)
    let fallbackOnlyTranscriptPipeline = VoicePipeline(
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
    let transcriptFallbackVM = AppViewModel(
        pipeline: fallbackOnlyTranscriptPipeline,
        permissions: StubPermissions(),
        performanceSampler: PerformanceSampler(),
        settingsStore: settingsStore
    )
    transcriptFallbackVM.skipOnboarding()
    await transcriptFallbackVM.simulatePressForTesting()
    await transcriptFallbackVM.simulateReleaseForTesting()
    try require(transcriptFallbackVM.lastError == "清洗模型不可用，已降级为仅转录", "pipeline fallback-to-transcript should keep transcript fallback message")

    let profileFallbackCleaner = RuleBasedTextCleaner(
        skillStore: InMemorySkillStore(),
        matcher: SkillMatcher(),
        generator: FailingPromptGenerator()
    )
    let profileFallbackPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: profileFallbackCleaner,
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics()
    )
    let profileFallbackVM = AppViewModel(
        pipeline: profileFallbackPipeline,
        permissions: StubPermissions(),
        performanceSampler: PerformanceSampler(),
        skillStore: InMemorySkillStore(),
        settingsStore: settingsStore
    )
    profileFallbackVM.skipOnboarding()
    await profileFallbackVM.simulatePressForTesting()
    await profileFallbackVM.simulateReleaseForTesting()
    try require(profileFallbackVM.lastError == "清洗模型不可用，已降级为规则清洗", "skill fallback should describe rule-based cleaning instead of transcript-only")
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
    let countingTranscriber = CountingStubTranscriber()
    let countingCleaner = CountingStubCleaner()
    let countingInjector = CountingStubInjector(results: [
        InjectResult(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: 5),
        InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 5)
    ])
    let recoverable = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: countingTranscriber,
        contextResolver: StubContextResolver(),
        cleaner: countingCleaner,
        injector: countingInjector,
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: RetryPolicy(timeoutMs: 3000, maxRetries: 1)
    )
    let recoverableSession = try recoverable.startRecording()
    let recoverableResult = try await recoverable.stopRecordingAndProcess(sessionId: recoverableSession)
    try require(recoverableResult.inject.success, "retry should recover transient injection failure")
    try require(countingTranscriber.callCount == 1, "inject retry should not rerun transcribe")
    try require(countingCleaner.callCount == 1, "inject retry should not rerun clean")
    try require(countingInjector.callCount == 2, "inject retry should only retry injection")

    let delayedTranscriber = CountingStubTranscriber()
    let delayedCleaner = CountingStubCleaner()
    let singleSuccessInjector = CountingStubInjector(results: [
        InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 50)
    ])
    let postInjectBudgetPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: delayedTranscriber,
        contextResolver: StubContextResolver(),
        cleaner: delayedCleaner,
        injector: singleSuccessInjector,
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: RetryPolicy(timeoutMs: 20, maxRetries: 1)
    )
    let postInjectBudgetSession = try postInjectBudgetPipeline.startRecording()
    let postInjectBudgetResult = try await postInjectBudgetPipeline.stopRecordingAndProcess(sessionId: postInjectBudgetSession)
    try require(postInjectBudgetResult.inject.success, "successful injection should not be turned into timeout after side effect")
    try require(postInjectBudgetResult.inject.latencyMs == 50, "successful inject should preserve observed side-effect latency")
    try require(singleSuccessInjector.callCount == 1, "successful injection should not write twice after budget is exceeded")
    try require(delayedTranscriber.callCount == 1, "post-inject success should keep transcribe single-shot")
    try require(delayedCleaner.callCount == 1, "post-inject success should keep clean single-shot")

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

@MainActor
func runRemoteTimeoutBudgetChecks() async throws {
    let remoteCleanPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSlowSuccess(latencyMs: 6_800),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: .remoteModelDefault
    )
    let remoteSession = try remoteCleanPipeline.startRecording()
    let remoteResult = try await remoteCleanPipeline.stopRecordingAndProcess(sessionId: remoteSession)
    try require(remoteResult.clean.cleanText == "远端加工：原始转写文本", "remote policy should keep successful slow clean result")
    try require(remoteResult.clean.usedFallback == false, "remote policy should avoid false transcript fallback for successful clean")
    try require(remoteResult.clean.latencyMs > 3000, "remote policy regression should prove clean latency exceeds old local budget")

    let remoteTimeoutPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriber(),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSlowSuccess(latencyMs: 10_500),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: .remoteModelDefault
    )
    let cleanFallbackSession = try remoteTimeoutPipeline.startRecording()
    let fallbackResult = try await remoteTimeoutPipeline.stopRecordingAndProcess(sessionId: cleanFallbackSession)
    try require(fallbackResult.clean.usedFallback, "remote policy should still fallback when clean exceeds remote budget")
    try require(fallbackResult.clean.cleanText == "原始转写文本", "over-budget remote clean should fallback to transcript")

    let remoteTranscribeTimeoutPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: StubTranscriberWithLatency(latencyMs: 10_500, text: "远端转写"),
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSuccess(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics(),
        retryPolicy: .remoteModelDefault
    )
    let timeoutSession = try remoteTranscribeTimeoutPipeline.startRecording()
    do {
        _ = try await remoteTranscribeTimeoutPipeline.stopRecordingAndProcess(sessionId: timeoutSession)
        try require(false, "remote policy should still timeout when transcribe exceeds remote budget")
    } catch let error as VoxErrorCode {
        try require(error == .timeout, "remote policy should preserve hard timeout for truly slow remote transcribe")
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
func runSelectedModuleRegressionChecks() throws {
    var settings = FileAppSettingsStore.defaultSettings
    settings.onboardingCompleted = true

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
        settingsStore: InMemorySettingsStore(settings: settings)
    )

    try require(vm.showOnboarding == false, "completed onboarding should hide onboarding")
    try require(vm.selectedModule == .home, "completed onboarding should start on home")

    vm.selectModule(.settings)
    try require(vm.selectedModule == .settings, "selectModule(.settings) should set selectedModule to settings")

    let previous = vm.selectedModule
    vm.selectModule(.settings)
    try require(vm.selectedModule == previous, "re-selecting settings should be a no-op")

    vm.selectModule(.home)
    vm.selectModule(.settings)
    try require(vm.selectedModule == .settings, "selectedModule should remain .settings after navigation cycle")

    vm.selectModule(.home)
    vm.selectModule(.settings)
    try require(vm.selectedModule == .settings, "selectedModule should remain stable across multiple navigation cycles")
}

@MainActor
func runMenuBarDisplayModeRegressionChecks() throws {
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
        settingsStore: InMemorySettingsStore(settings: FileAppSettingsStore.defaultSettings)
    )

    vm.appSettings.menuBarDisplayMode = .iconOnly
    vm.appSettings.showRecentSummary = false
    try require(vm.appSettings.menuBarDisplayMode == .iconOnly, "menuBarDisplayMode should store iconOnly")
    try require(vm.appSettings.showRecentSummary == false, "iconOnly should keep recent summary hidden")

    vm.appSettings.menuBarDisplayMode = .iconAndSummary
    vm.appSettings.showRecentSummary = true
    try require(vm.appSettings.menuBarDisplayMode == .iconAndSummary, "menuBarDisplayMode should store iconAndSummary")
    try require(vm.appSettings.showRecentSummary, "iconAndSummary should keep recent summary visible")

    vm.menuBarSummary = "Issue 3 regression summary"
    let summary: String = vm.menuBarSummary
    try require(summary == "Issue 3 regression summary", "menuBarSummary should be readable as String")

    vm.appSettings.menuBarDisplayMode = .iconAndSummary
    vm.appSettings.showRecentSummary = true
    vm.menuBarSummary = "Dynamic summary text"

    let displayMode: MenuBarDisplayMode = vm.appSettings.menuBarDisplayMode
    let showSummary: Bool = vm.appSettings.showRecentSummary
    let dynamicSummary: String = vm.menuBarSummary

    try require(displayMode == .iconAndSummary, "ViewModel should expose menuBarDisplayMode")
    try require(dynamicSummary == "Dynamic summary text", "ViewModel should expose menuBarSummary as String")
    try require(showSummary, "ViewModel should expose showRecentSummary flag")

    vm.appSettings.menuBarDisplayMode = .iconOnly
    vm.setMenuBarSummaryVisible(false)
    let iconOnlySummary: String = vm.menuBarSummary
    try require(iconOnlySummary.isEmpty, "iconOnly mode should result in empty menuBarSummary")
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
        performanceSampler: PerformanceSampler(),
        settingsStore: InMemorySettingsStore()
    )
    try require(onboardingVM.showOnboarding, "onboarding should show when permissions missing")
    try require(onboardingVM.onboardingStep == 1, "onboarding should start from microphone step")
    await onboardingVM.requestPermission(.microphone)
    try require(onboardingVM.onboardingStep == 2, "after microphone should move to accessibility step")
    await onboardingVM.requestPermission(.accessibility)
    try require(onboardingVM.onboardingStep == 3, "after accessibility should move to speech step")
    await onboardingVM.requestPermission(.speechRecognition)
    try require(onboardingVM.showOnboarding == true, "onboarding should stay open until trial run passes")
    try require(onboardingVM.onboardingStep == 4, "after all permissions should move to trial run step")

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
        performanceSampler: PerformanceSampler(),
        settingsStore: InMemorySettingsStore()
    )
    await denyVM.simulatePressForTesting()
    try require(denyVM.stateText == "Failed", "press with missing permission should fail")
    try require(denyVM.actionTitle == "打开系统设置", "missing permission should expose settings CTA")
    try require(denyVM.recommendedSettingItem == .microphone, "missing permission should recommend microphone settings")
    try require(denyVM.speechReadiness == .unavailable(.permissionRequired), "missing permission should expose unavailable speech readiness")
    try require(denyVM.speechStatus == "不可用：权限未就绪", "missing permission should expose detailed speech status")

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
        performanceSampler: PerformanceSampler(),
        settingsStore: InMemorySettingsStore()
    )
    await timeoutVM.simulatePressForTesting()
    await timeoutVM.simulateReleaseForTesting()
    try require(timeoutVM.canRetry, "timeout failure should allow retry")
    try require(timeoutVM.actionTitle == "重试本次", "timeout failure should show retry CTA")
    try require(timeoutVM.speechReadiness == .unavailable(.unavailable), "timeout failure should mark speech readiness unavailable")
    await timeoutVM.retryLatest()
    try require(timeoutVM.stateText == "Idle", "retry action should reset to idle")
    try require(timeoutVM.canRetry == false, "retry action should clear retry flag")
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
func runWarmupModeChecks() async throws {
    let logger = StubLogger()
    let service = SpeechTranscriberWarmupService(logger: logger)
    let locale = Locale(identifier: "zh-CN")

    // 验证初始状态
    let initialState = await service.state
    try require(initialState == .idle, "warmup service initial state should be idle")

    // 测试 warmup 启动
    let warmupResult = await service.warmup(locale: locale, waitForCompletion: false)
    try require(warmupResult == true, "warmup should start successfully")

    // 验证状态已改变（不是 idle）
    let startedState = await service.state
    try require(startedState != .idle, "warmup should transition from idle")

    // 测试缓存命中：同 locale 再次 warmup
    let cachedStart = Date()
    let cachedResult = await service.warmup(locale: locale, waitForCompletion: false)
    let cachedElapsed = Date().timeIntervalSince(cachedStart)
    try require(cachedResult == true, "cached warmup should succeed")
    try require(cachedElapsed < 0.1, "cached warmup should be fast (< 100ms)")

    // 测试不同 locale 触发新 warmup
    let enLocale = Locale(identifier: "en-US")
    let enResult = await service.warmup(locale: enLocale, waitForCompletion: false)
    try require(enResult == true, "different locale warmup should start")

    // 测试 isReady 方法
    let isReadyResult = await service.isReady(for: locale)
    // 由于 warmup 是异步的，isReady 可能返回 true 或 false
    // 我们只需要验证方法不崩溃即可
    _ = isReadyResult

    // 测试 deallocate
    await service.deallocate(locale: locale)
    let afterDeallocState = await service.state
    // 状态应该被重置（如果当前是该 locale 的 ready 状态）
    _ = afterDeallocState

    // 测试 reset
    await service.reset()
    let resetState = await service.state
    try require(resetState == .idle, "reset should return to idle state")
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
func runWarmupPerformanceChecks() async throws {
    let logger = StubLogger()
    let service = SpeechTranscriberWarmupService(logger: logger)
    let locale = Locale(identifier: "zh-CN")

    // 测试 warmup 启动延迟（应小于 50ms）
    let start = Date()
    let result = await service.warmup(locale: locale, waitForCompletion: false)
    let elapsed = Date().timeIntervalSince(start)

    try require(result == true, "warmup should start")
    try require(elapsed < 0.05, "warmup startup latency should be < 50ms (actual: \(elapsed * 1000)ms)")

    // 等待状态稳定
    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

    // 测试缓存命中延迟（应小于 10ms）
    let cachedStart = Date()
    let cachedResult = await service.warmup(locale: locale, waitForCompletion: false)
    let cachedElapsed = Date().timeIntervalSince(cachedStart)

    try require(cachedResult == true, "cached warmup should succeed")
    try require(cachedElapsed < 0.01, "cache hit latency should be < 10ms (actual: \(cachedElapsed * 1000)ms)")
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
func runWarmupIntegrationChecks() async throws {
    let logger = StubLogger()
    let session = SpeechTranscriberWarmupService(logger: logger)
    let locale = Locale(identifier: "zh-CN")
    let result = await session.warmup(locale: locale, waitForCompletion: false)
    try require(result == true, "warmup service integration should start")
    _ = await session.isReady(for: locale)
    await session.deallocate(locale: locale)
    await session.reset()
    let state = await session.state
    try require(state == .idle, "warmup service integration reset should return idle")
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

    let transcribeP50 = pipeline.percentileTranscribeLatency(0.5)
    let cleanP50 = pipeline.percentileCleanLatency(0.5)
    let injectP50 = pipeline.percentileInjectLatency(0.5)
    try require(transcribeP50 != nil, "transcribe stage should have recorded latency metrics")
    try require(cleanP50 != nil, "clean stage should have recorded latency metrics")
    try require(injectP50 != nil, "inject stage should have recorded latency metrics")
    try require((transcribeP50 ?? Int.max) < 1000, "transcribe P50 should be below 1000ms")
    try require((cleanP50 ?? Int.max) < 1000, "clean P50 should be below 1000ms")
    try require((injectP50 ?? Int.max) < 500, "inject P50 should be below 500ms")
}

@MainActor
func runPipelineObservabilityChecks() async throws {
    let metrics = SelfCheckMetrics()
    let transcriber = CountingStubTranscriber()
    let pipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: transcriber,
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSuccess(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: metrics
    )
    let sessionId = try pipeline.startRecording()
    _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)
    try require(metrics.events.contains("pipeline.stage.transcribe"), "transcribe stage metric should be recorded")
    try require(metrics.events.contains("pipeline.stage.clean"), "clean stage metric should be recorded")
    try require(metrics.events.contains("pipeline.stage.inject"), "inject stage metric should be recorded")

    let observedTranscriber = SelfCheckObservedTranscriber()
    let observedPipeline = VoicePipeline(
        stateMachine: StubStateStore(),
        audioCapture: StubAudio(),
        transcriber: observedTranscriber,
        contextResolver: StubContextResolver(),
        cleaner: StubCleanerSuccess(),
        injector: StubInjector(),
        permissions: StubPermissions(),
        logger: StubLogger(),
        metrics: StubMetrics()
    )
    var observedStages: [VoicePipeline.Stage] = []
    observedPipeline.stageObserver = { event in
        if event.phase == .completed {
            observedStages.append(event.stage)
        }
    }
    let observedSession = try observedPipeline.startRecording()
    _ = try await observedPipeline.stopRecordingAndProcess(sessionId: observedSession)
    try require(observedStages.contains(.assetCheck), "asset-check stage should be observable")
    try require(observedStages.contains(.assetInstall), "asset-install stage should be observable")
    try require(observedStages.contains(.analyzerCreate), "analyzer-create stage should be observable")
    try require(observedStages.contains(.analyzerWarmup), "analyzer-warmup stage should be observable")

    let vm = AppViewModel(
        pipeline: observedPipeline,
        permissions: StubPermissions(),
        performanceSampler: PerformanceSampler(),
        settingsStore: InMemorySettingsStore(settings: FileAppSettingsStore.defaultSettings)
    )
    vm.skipOnboarding()
    await vm.simulatePressForTesting()
    let releaseTask = Task { await vm.simulateReleaseForTesting() }
    try? await Task.sleep(nanoseconds: 10_000_000)
    try require(vm.processingFeedbackText.isEmpty == false, "processing feedback should be exposed during pipeline processing")
    await releaseTask.value
    try require(vm.processingFeedbackText == "已完成", "successful pipeline should expose completed feedback")
}

@MainActor
final class SelfCheckObservedTranscriber: SpeechTranscribing, VoicePipelineStageReporting {
    var stageObserver: VoicePipeline.StageObserver?

    func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        stageObserver?(.init(stage: .assetCheck, phase: .started))
        stageObserver?(.init(stage: .assetCheck, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        stageObserver?(.init(stage: .assetInstall, phase: .started))
        stageObserver?(.init(stage: .assetInstall, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        stageObserver?(.init(stage: .analyzerCreate, phase: .started))
        stageObserver?(.init(stage: .analyzerCreate, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        stageObserver?(.init(stage: .analyzerWarmup, phase: .started))
        stageObserver?(.init(stage: .analyzerWarmup, phase: .completed, success: true, errorCode: nil, latencyMs: 1))
        return SpeechTranscription(text: "原始转写文本", latencyMs: 5, usedOnDevice: true)
    }
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
        try runKeyCodeToStringRegressionChecks()
        try runCleaningModeCodecChecks()
        try runErrorDetailChecks()
        try runAppSettingsOnboardingChecks()
        try await runCleanerChecks()
        try await runPromptToLLMInjectionChecks()
        try runBootstrapRemoteRuntimeChecks()
        try runHotSwitchRuntimeChecks()
        try await runFallbackMessageChecks()
        try await runPipelineFallbackChecks()
        try await runPermissionErrorChecks()
        try await runRetryChecks()
        try await runTimeoutChecks()
        try await runRemoteTimeoutBudgetChecks()

        // Warmup/Readiness 模式自检
        if #available(macOS 26.0, iOS 26.0, *) {
            try await runWarmupModeChecks()
            try await runWarmupPerformanceChecks()
            try await runWarmupIntegrationChecks()
        }
        try runFnMonitorChecks()
        try runClipboardInjectorChecks()
        try runSelectedModuleRegressionChecks()
        try runMenuBarDisplayModeRegressionChecks()
        try await runAppStateMachineChecks()
        try await runPerformanceThresholdChecks()
        try await runPipelineObservabilityChecks()
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

// MARK: - Model Retention Policy Checks

func checkModelRetentionPolicy() -> [CheckResult] {
    var results: [CheckResult] = []

    // Check 1: Device Tier Detection
    results.append(checkDeviceTierDetection())

    // Check 2: Retention Decision Logic
    results.append(checkRetentionDecisionLogic())

    // Check 3: Resource Pressure Evaluation
    results.append(checkResourcePressureEvaluation())

    // Check 4: Platform-specific Behavior
    results.append(checkPlatformSpecificBehavior())

    return results
}

func checkDeviceTierDetection() -> CheckResult {
    let checkName = "DeviceTier Detection"

    // Verify device tier can be detected
    let deviceTier = DeviceTierDetector.detect()

    // On macOS, we should detect either Apple Silicon or Intel
    #if os(macOS)
    switch deviceTier {
    case .appleSilicon, .intelOrConstrained:
        return CheckResult(name: checkName, passed: true)
    case .unsupported:
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Device tier detection returned unsupported on macOS"
        )
    }
    #else
    return CheckResult(
        name: checkName,
        passed: deviceTier == .unsupported,
        error: deviceTier != .unsupported ? "Expected unsupported on non-macOS platform" : nil
    )
    #endif
}

func checkRetentionDecisionLogic() -> CheckResult {
    let checkName = "Retention Decision Logic"

    // Test Apple Silicon with normal pressure
    let appleSiliconPolicy = ModelRetentionPolicy(
        configuration: .default,
        deviceTier: .appleSilicon
    )

    let normalSnapshot = RuntimeResourceSnapshot(
        cpuUsagePercent: 10.0,
        memoryMB: 150.0
    )

    let normalDecision = appleSiliconPolicy.evaluate(snapshot: normalSnapshot)
    guard normalDecision == .retainAll else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Apple Silicon with normal pressure should retain all, got \(normalDecision)"
        )
    }

    // Test critical pressure on Apple Silicon
    let criticalSnapshot = RuntimeResourceSnapshot(
        cpuUsagePercent: 65.0,
        memoryMB: 150.0
    )

    let criticalDecision = appleSiliconPolicy.evaluate(snapshot: criticalSnapshot)
    guard criticalDecision == .releaseAssetsOnly else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Apple Silicon with critical pressure should release assets only, got \(criticalDecision)"
        )
    }

    // Test Intel with critical pressure
    let intelPolicy = ModelRetentionPolicy(
        configuration: .default,
        deviceTier: .intelOrConstrained
    )

    let intelCriticalDecision = intelPolicy.evaluate(snapshot: criticalSnapshot)
    guard intelCriticalDecision == .releaseAll else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Intel with critical pressure should release all, got \(intelCriticalDecision)"
        )
    }

    return CheckResult(name: checkName, passed: true)
}

func checkResourcePressureEvaluation() -> CheckResult {
    let checkName = "Resource Pressure Evaluation"

    let config = ResourcePressureConfiguration.default
    let sampler = PerformanceSampler(pressureConfiguration: config)

    // Test normal pressure
    let normalSnapshot = RuntimeResourceSnapshot(
        cpuUsagePercent: 10.0,
        memoryMB: 150.0
    )
    let normalPressure = sampler.evaluatePressure(snapshot: normalSnapshot)
    guard normalPressure == .normal else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Expected normal pressure for low CPU/memory, got \(normalPressure)"
        )
    }

    // Test elevated CPU pressure
    let elevatedCPUSnapshot = RuntimeResourceSnapshot(
        cpuUsagePercent: 35.0,
        memoryMB: 150.0
    )
    let elevatedCPUPressure = sampler.evaluatePressure(snapshot: elevatedCPUSnapshot)
    guard elevatedCPUPressure == .elevated else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Expected elevated pressure for 35% CPU, got \(elevatedCPUPressure)"
        )
    }

    // Test critical memory pressure
    let criticalMemorySnapshot = RuntimeResourceSnapshot(
        cpuUsagePercent: 10.0,
        memoryMB: 550.0
    )
    let criticalMemoryPressure = sampler.evaluatePressure(snapshot: criticalMemorySnapshot)
    guard criticalMemoryPressure == .critical else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Expected critical pressure for 550MB memory, got \(criticalMemoryPressure)"
        )
    }

    return CheckResult(name: checkName, passed: true)
}

func checkPlatformSpecificBehavior() -> CheckResult {
    let checkName = "Platform-Specific Behavior"

    // Test unsupported platform always releases all
    let unsupportedPolicy = ModelRetentionPolicy(
        configuration: .default,
        deviceTier: .unsupported
    )

    let normalSnapshot = RuntimeResourceSnapshot(
        cpuUsagePercent: 10.0,
        memoryMB: 150.0
    )

    let unsupportedDecision = unsupportedPolicy.evaluate(snapshot: normalSnapshot)
    guard unsupportedDecision == .releaseAll else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Unsupported platform should always release all, got \(unsupportedDecision)"
        )
    }

    // Test retention enabled status
    let appleSiliconPolicy = ModelRetentionPolicy(
        configuration: .default,
        deviceTier: .appleSilicon
    )

    guard appleSiliconPolicy.isRetentionEnabled else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Apple Silicon should have retention enabled"
        )
    }

    // Test disabled retention on Intel
    let disabledIntelPolicy = ModelRetentionPolicy(
        configuration: RetentionPolicyConfiguration(enableOnConstrainedDevices: false),
        deviceTier: .intelOrConstrained
    )

    guard !disabledIntelPolicy.isRetentionEnabled else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Intel should have retention disabled when configured"
        )
    }

    // Test recommended configuration
    let appleSiliconConfig = appleSiliconPolicy.recommendedConfiguration
    guard appleSiliconConfig.cpuElevatedThreshold == 30.0 else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Apple Silicon should use default config with 30% CPU threshold"
        )
    }

    let intelPolicy = ModelRetentionPolicy(
        configuration: .default,
        deviceTier: .intelOrConstrained
    )
    let intelConfig = intelPolicy.recommendedConfiguration
    guard intelConfig.cpuElevatedThreshold == 20.0 else {
        return CheckResult(
            name: checkName,
            passed: false,
            error: "Intel should use conservative config with 20% CPU threshold"
        )
    }

    return CheckResult(name: checkName, passed: true)
}
