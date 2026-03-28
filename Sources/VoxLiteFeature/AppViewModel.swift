import Foundation
import VoxLiteCore
import VoxLiteDomain
import VoxLiteInput
import VoxLiteOutput
import VoxLiteSystem

public enum SpeechReadinessState: Equatable, Sendable {
    public enum FailureReason: Equatable, Sendable {
        case permissionRequired
        case recordingUnavailable
        case recordingTooShort
        case assetDownloadFailed
        case modelInstallFailed
        case unavailable
    }

    case notReady
    case downloading
    case installing
    case ready
    case unavailable(FailureReason)
    case terminated(FailureReason)

    public var statusText: String {
        switch self {
        case .notReady:
            return "未就绪：待录音"
        case .downloading:
            return "下载中：语音资产"
        case .installing:
            return "安装中：语音模型"
        case .ready:
            return "已就绪"
        case .unavailable(.permissionRequired):
            return "不可用：权限未就绪"
        case .unavailable(.recordingUnavailable):
            return "不可用：录音设备忙碌"
        case .unavailable(.assetDownloadFailed):
            return "不可用：语音资产下载失败"
        case .unavailable(.modelInstallFailed):
            return "不可用：语音模型安装失败"
        case .unavailable(.recordingTooShort):
            return "不可用：录音过短"
        case .unavailable(.unavailable):
            return "不可用：语音识别暂不可用"
        case .terminated(.recordingTooShort):
            return "终止：录音过短"
        case .terminated(.assetDownloadFailed):
            return "终止：语音资产下载失败"
        case .terminated(.modelInstallFailed):
            return "终止：语音模型安装失败"
        case .terminated(.recordingUnavailable):
            return "终止：录音设备忙碌"
        case .terminated(.permissionRequired):
            return "终止：权限未就绪"
        case .terminated(.unavailable):
            return "终止：语音识别不可用"
        }
    }
}

public enum FoundationModelReadinessState: Equatable, Sendable {
    public enum FailureReason: Equatable, Sendable {
        case modelLoading
        case appleIntelligenceDisabled
        case deviceNotEligible
        case unavailable
    }

    case ready
    case notReady(FailureReason)
    case unavailable(FailureReason)
    case terminated(FailureReason)

    public var statusText: String {
        switch self {
        case .ready:
            return "已就绪"
        case .notReady(.modelLoading):
            return "未就绪：Foundation Model 正在加载"
        case .notReady(.appleIntelligenceDisabled):
            return "未就绪：Apple Intelligence 未开启"
        case .notReady(.deviceNotEligible):
            return "未就绪：当前设备不支持"
        case .notReady(.unavailable):
            return "未就绪：Foundation Model 暂不可用"
        case .unavailable(.appleIntelligenceDisabled):
            return "不可用：请先开启 Apple Intelligence"
        case .unavailable(.modelLoading):
            return "不可用：Foundation Model 尚未完成加载"
        case .unavailable(.unavailable):
            return "不可用：Foundation Model 暂时不可用"
        case .unavailable(.deviceNotEligible):
            return "不可用：当前设备不支持 Apple Foundation Model"
        case .terminated(.deviceNotEligible):
            return "终止：当前设备不支持 Apple Foundation Model"
        case .terminated(.appleIntelligenceDisabled):
            return "终止：Apple Intelligence 未开启"
        case .terminated(.modelLoading):
            return "终止：Foundation Model 未完成加载"
        case .terminated(.unavailable):
            return "终止：Foundation Model 不可用"
        }
    }
}

public enum ProcessingFeedbackState: Equatable, Sendable {
    case idle
    case preparing
    case transcribing
    case cleaning
    case injecting
    case completed
    case failed

    public var defaultText: String {
        switch self {
        case .idle:
            return ""
        case .preparing:
            return "准备中..."
        case .transcribing:
            return "转写中..."
        case .cleaning:
            return "清洗中..."
        case .injecting:
            return "注入中..."
        case .completed:
            return "已完成"
        case .failed:
            return "处理失败"
        }
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var showOnboarding: Bool = true
    @Published public var onboardingStep: Int = 0
    @Published public var permissionSnapshot: PermissionSnapshot = .init(
        microphoneGranted: false,
        speechRecognitionGranted: false,
        accessibilityGranted: false
    )
    @Published public var stateText: String = "Idle"
    @Published public var sceneHint: String = "当前为沟通风格：短句、直接、单段输出。"
    @Published public var cleanedText: String = ""
    @Published public var lastError: String = ""
    @Published public var actionTitle: String = ""
    @Published public var canRetry: Bool = false
    @Published public var recommendedSettingItem: PermissionItem?
    @Published public var resourceHint: String = ""
    @Published public var showRecordingAnimation: Bool = false
    @Published public var hotKeySettings: HotKeySettings = HotKeySettings()
    @Published public var speechStatus: String = "未知"
    @Published public var foundationModelStatus: String = "未知"
    @Published public var speechReadiness: SpeechReadinessState = .notReady
    @Published public var foundationModelReadiness: FoundationModelReadinessState = .unavailable(.unavailable)
    @Published public var foundationModelAvailability: FoundationModelAvailabilityState = .unavailable
    @Published public var processingFeedbackState: ProcessingFeedbackState = .idle
    @Published public var processingFeedbackText: String = ""
    @Published public var sttModelName: String = ""
    @Published public var llmModelName: String = ""
    @Published public var cleanStyleTag: String = "未处理"
    @Published public var selectedModule: MainModule = .welcome
    @Published public var historyItems: [TranscriptHistoryItem] = []
    @Published public var skillSnapshot: SkillConfigSnapshot = FileSkillStore.defaultSnapshot
    @Published public var appSettings: AppSettings = FileAppSettingsStore.defaultSettings
    @Published public var menuBarSummary: String = ""
    @Published public var trialRunPassed: Bool = false

    public var onReleaseResources: (() async -> Void)?

    private var pipeline: VoicePipeline
    private let permissions: PermissionManaging
    private let performanceSampler: PerformanceSampler
    private let historyStore: HistoryStore
    private let skillStore: SkillStore
    private let settingsStore: AppSettingsStore
    private let launchAtLoginManager: LaunchAtLoginManaging
    private var foundationModelAvailabilityProvider: any FoundationModelAvailabilityProviding
    private let runtimeChainReloader: (() -> (pipeline: VoicePipeline, availabilityProvider: any FoundationModelAvailabilityProviding))?
    private let skillMatcher = SkillMatcher()
    private var monitor: HotKeyMonitor?
    private var activeSessionId: UUID?

    public init(
        pipeline: VoicePipeline,
        permissions: PermissionManaging,
        performanceSampler: PerformanceSampler,
        historyStore: HistoryStore? = nil,
        skillStore: SkillStore? = nil,
        settingsStore: AppSettingsStore? = nil,
        launchAtLoginManager: LaunchAtLoginManaging? = nil,
        foundationModelAvailabilityProvider: any FoundationModelAvailabilityProviding = FoundationModelAvailabilityProbe(),
        runtimeChainReloader: (() -> (pipeline: VoicePipeline, availabilityProvider: any FoundationModelAvailabilityProviding))? = nil
    ) {
        self.pipeline = pipeline
        self.permissions = permissions
        self.performanceSampler = performanceSampler
        self.historyStore = historyStore ?? FileHistoryStore()
        self.skillStore = skillStore ?? FileSkillStore()
        self.settingsStore = settingsStore ?? FileAppSettingsStore()
        self.launchAtLoginManager = launchAtLoginManager ?? UserDefaultsLaunchAtLoginManager()
        self.foundationModelAvailabilityProvider = foundationModelAvailabilityProvider
        self.runtimeChainReloader = runtimeChainReloader
        self.permissionSnapshot = permissions.currentPermissionSnapshot()
        let settings = self.settingsStore.loadSettings()
        self.appSettings = settings
        let onboardingDone = settings.onboardingCompleted && permissionSnapshot.allGranted
        self.showOnboarding = !onboardingDone
        self.onboardingStep = onboardingDone ? 5 : (permissionSnapshot.allGranted ? 4 : 1)
        self.selectedModule = onboardingDone ? .home : .welcome
        self.historyItems = self.historyStore.loadHistory()
        self.skillSnapshot = self.skillStore.loadSkills()
        self.menuBarSummary = historyItems.first?.outputText ?? ""
        self.hotKeySettings.conflictMessage = ""
        configurePipelineObserver()
        refreshFoundationModelAvailability()
        refreshModelNames()
        configureMonitor()
    }

    public func resetResources() async {
        await pipeline.resetResources()
    }

    public func handleMemoryWarning() {
        Task { @MainActor in
            await onReleaseResources?()
        }
    }

    public func handleDidEnterBackground() {
        Task { @MainActor in
            await onReleaseResources?()
        }
    }

    public func startMonitor() {
        if !showOnboarding || permissionSnapshot.allGranted {
            monitor?.start()
        }
    }

    public func stopMonitor() {
        monitor?.stop()
    }

    public func switchScene(to category: AppCategory) {
        switch category {
        case .communication:
            sceneHint = "当前为沟通风格：短句、直接、单段输出。"
        case .development:
            sceneHint = "当前为开发风格：命名规范与提交语气优先。"
        case .writing:
            sceneHint = "当前为写作风格：结构化、书面化表达优先。"
        case .general:
            sceneHint = "当前为通用风格。"
        }
    }

    public func switchToCommunication() {
        switchScene(to: .communication)
    }

    public func switchToDevelopment() {
        switchScene(to: .development)
    }

    public func switchToWriting() {
        switchScene(to: .writing)
    }

    public func selectModule(_ module: MainModule) {
        selectedModule = module
    }

    public func reloadSkillSnapshot() {
        skillSnapshot = skillStore.loadSkills()
    }

    @discardableResult
    public func addCustomSkill(name: String, template: String, styleHint: String) -> String {
        let id = UUID().uuidString.lowercased()
        let profile = SkillProfile(
            id: id,
            name: name,
            type: .custom,
            template: template,
            styleHint: styleHint
        )
        skillSnapshot.profiles.append(profile)
        saveSkills()
        return id
    }

    public func updateSkill(_ profile: SkillProfile) {
        guard let idx = skillSnapshot.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        skillSnapshot.profiles[idx] = profile
        saveSkills()
    }

    @discardableResult
    public func deleteSkill(_ skillId: String) -> Bool {
        guard let idx = skillSnapshot.profiles.firstIndex(where: { $0.id == skillId }) else { return false }
        if skillSnapshot.profiles[idx].type == .preinstalled {
            return false
        }
        skillSnapshot.profiles.remove(at: idx)
        let removedBundles = Set(skillSnapshot.matching.bundleSkillMap.filter { $0.value == skillId }.map { $0.key })
        skillSnapshot.matching.bundleSkillMap = skillSnapshot.matching.bundleSkillMap.filter { $0.value != skillId }
        for bundleId in removedBundles {
            skillSnapshot.matching.bundleDisplayNameMap.removeValue(forKey: bundleId)
        }
        skillSnapshot.matching.categorySkillMap = skillSnapshot.matching.categorySkillMap.filter { $0.value != skillId }
        if skillSnapshot.matching.defaultSkillId == skillId {
            skillSnapshot.matching.defaultSkillId = "transcribe"
        }
        saveSkills()
        return true
    }

    public func bindBundle(_ bundleId: String, skillId: String) {
        skillSnapshot.matching.bundleSkillMap[bundleId] = skillId
        saveSkills()
    }

    public func setBundleBindings(skillId: String, bindings: [AppBinding]) {
        let staleBundles = skillSnapshot.matching.bundleSkillMap
            .filter { $0.value == skillId }
            .map(\.key)
        for bundleId in staleBundles {
            skillSnapshot.matching.bundleSkillMap.removeValue(forKey: bundleId)
            skillSnapshot.matching.bundleDisplayNameMap.removeValue(forKey: bundleId)
        }
        for binding in bindings {
            skillSnapshot.matching.bundleSkillMap[binding.bundleId] = skillId
            skillSnapshot.matching.bundleDisplayNameMap[binding.bundleId] = binding.appName
        }
        saveSkills()
    }

    public func bindingsForSkill(_ skillId: String) -> [AppBinding] {
        skillSnapshot.matching.bundleSkillMap
            .filter { $0.value == skillId }
            .map { bundleId, _ in
                AppBinding(
                    bundleId: bundleId,
                    appName: skillSnapshot.matching.bundleDisplayNameMap[bundleId] ?? bundleId
                )
            }
            .sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    public func bindCategory(_ category: AppCategory, skillId: String) {
        skillSnapshot.matching.categorySkillMap[category] = skillId
        saveSkills()
    }

    public func setDefaultSkill(_ skillId: String) {
        skillSnapshot.matching.defaultSkillId = skillId
        skillSnapshot.matching.categorySkillMap[.general] = skillId
        saveSkills()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        appSettings.launchAtLoginEnabled = enabled
        launchAtLoginManager.setEnabled(enabled)
        saveSettings()
    }

    public func setMenuBarSummaryVisible(_ visible: Bool) {
        appSettings.showRecentSummary = visible
        if !visible {
            menuBarSummary = ""
        } else {
            updateMenuBarSummary()
        }
        saveSettings()
    }

    public func skipOnboarding() {
        onboardingStep = 4
        showOnboarding = false
        selectedModule = .home
        startMonitor()
    }

    public func refreshPermissionSnapshot() {
        permissionSnapshot = permissions.currentPermissionSnapshot()
        updateOnboardingStep()
    }

    public func requestPermission(_ item: PermissionItem) async {
        _ = await permissions.requestPermission(item)
        permissionSnapshot = permissions.currentPermissionSnapshot()
        updateOnboardingStep()
    }

    public func openSettingForRecommendedPermission() {
        guard let recommendedSettingItem else { return }
        permissions.openSystemSettings(for: recommendedSettingItem)
    }

    public func openSystemSettings(for item: PermissionItem) {
        permissions.openSystemSettings(for: item)
    }

    @discardableResult
    public func saveRemoteModelSettings() -> Bool {
        saveSettings()
        guard activeSessionId == nil else {
            lastError = "当前正在处理语音，配置已保存，将在本轮结束后生效"
            return false
        }
        guard let runtimeChainReloader else {
            refreshModelNames()
            refreshFoundationModelAvailability()
            reloadSkillSnapshot()
            return true
        }
        let runtimeChain = runtimeChainReloader()
        pipeline = runtimeChain.pipeline
        foundationModelAvailabilityProvider = runtimeChain.availabilityProvider
        configurePipelineObserver()
        appSettings = settingsStore.loadSettings()
        refreshModelNames()
        refreshFoundationModelAvailability()
        reloadSkillSnapshot()
        return true
    }

    public func resetOnboarding() {
        appSettings.onboardingCompleted = false
        trialRunPassed = false
        showOnboarding = true
        saveSettings()
        refreshPermissionSnapshot()
        selectedModule = .welcome
    }

    public func retryLatest() async {
        guard canRetry else { return }
        lastError = "请按住快捷键重新录入"
        actionTitle = ""
        canRetry = false
        stateText = "Idle"
        setProcessingFeedback(.idle)
    }

    public func simulatePressForTesting() async {
        await handlePress()
    }

    public func simulateReleaseForTesting() async {
        await handleRelease()
    }

    public func updateHotKeyConfiguration(_ config: HotKeyConfiguration) {
        hotKeySettings.updateConfiguration(config)
        monitor?.updateConfiguration(config)
        let conflict = hotKeySettings.checkForConflicts()
        hotKeySettings.hasConflict = conflict.hasConflict
        hotKeySettings.conflictMessage = conflict.message
        appSettings.hotKeyDescription = config.displayString.isEmpty ? "Fn" : config.displayString
        saveSettings()
    }

    private func updateOnboardingStep() {
        guard !appSettings.onboardingCompleted else { return }
        if !permissionSnapshot.microphoneGranted {
            onboardingStep = 1
        } else if !permissionSnapshot.accessibilityGranted {
            onboardingStep = 2
        } else if !permissionSnapshot.speechRecognitionGranted {
            onboardingStep = 3
        } else if !trialRunPassed {
            onboardingStep = 4
        } else {
            onboardingStep = 5
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        showOnboarding = false
        appSettings.onboardingCompleted = true
        saveSettings()
        selectedModule = .home
        startMonitor()
    }

    private func configureMonitor() {
        monitor?.stop()
        monitor = HotKeyMonitor(
            configuration: hotKeySettings.configuration,
            onPress: { [weak self] in
                Task { @MainActor in
                    await self?.handlePress()
                }
            },
            onRelease: { [weak self] in
                Task { @MainActor in
                    await self?.handleRelease()
                }
            }
        )
        lastError = ""
        stateText = "Idle"
        applySpeechReadiness(.notReady)
        cleanedText = ""
        activeSessionId = nil
        canRetry = false
        actionTitle = ""
        setProcessingFeedback(.idle)
    }

    private func handlePress() async {
        permissionSnapshot = permissions.currentPermissionSnapshot()
        refreshFoundationModelAvailability()
        applySpeechReadiness(.notReady)
        guard permissionSnapshot.allGranted else {
            stateText = "Failed"
            setProcessingFeedback(.idle)
            showOnboarding = true
            updateOnboardingStep()
            lastError = "权限未就绪，请先完成授权"
            actionTitle = "打开系统设置"
            recommendedSettingItem = missingPermissionItem()
            canRetry = false
            applySpeechReadiness(.unavailable(.permissionRequired))
            return
        }
        do {
            let sessionId = try pipeline.startRecording()
            activeSessionId = sessionId
            stateText = "Recording"
            setProcessingFeedback(.idle)
            lastError = ""
            actionTitle = ""
            recommendedSettingItem = nil
            canRetry = false
            showRecordingAnimation = true
        } catch {
            if let voxError = error as? VoxErrorCode, voxError == .recordingUnavailable {
                stateText = "Idle"
                setProcessingFeedback(.idle)
                lastError = "录音设备忙碌或触发过快，请稍后重试"
                actionTitle = ""
                recommendedSettingItem = nil
                canRetry = false
                applySpeechReadiness(.unavailable(.recordingUnavailable))
                return
            }
            stateText = "Failed"
            setProcessingFeedback(.idle)
            lastError = "权限或录音不可用"
            actionTitle = "打开系统设置"
            recommendedSettingItem = .microphone
            canRetry = false
            applySpeechReadiness(.unavailable(.unavailable))
        }
    }

    private func handleRelease() async {
        guard let activeSessionId else { return }
        showRecordingAnimation = false
        do {
            stateText = "Processing"
            applySpeechReadiness(.installing)
            setProcessingFeedback(.preparing)
            let result = try await pipeline.stopRecordingAndProcess(sessionId: activeSessionId)
            stateText = result.inject.success ? "Done" : "Failed"
            cleanedText = result.clean.cleanText
            trialRunPassed = result.inject.success
            cleanStyleTag = result.clean.styleTag
            setProcessingFeedback(result.inject.success ? .completed : .failed)
            applySpeechReadiness(result.transcript.success ? .ready : .unavailable(.unavailable))
            refreshFoundationModelAvailability()
            if showOnboarding && trialRunPassed && permissionSnapshot.allGranted {
                updateOnboardingStep()
            }
            if result.clean.usedFallback {
                lastError = fallbackMessage(for: result.clean)
                actionTitle = ""
                canRetry = false
            } else {
                lastError = result.inject.success ? "" : "注入失败，已复制到剪贴板，可按 Cmd+V 粘贴"
                actionTitle = result.inject.success ? "" : "重试本次"
                canRetry = !result.inject.success
            }
            recommendedSettingItem = nil
            appendHistory(from: result)
            updateMenuBarSummary()
            pipeline.resetToIdle()
            self.activeSessionId = nil
            recordMetricSummary()
        } catch {
            if let voxError = error as? VoxErrorCode, voxError == .recordingUnavailable {
                stateText = "Idle"
                lastError = "按住快捷键稍久一点再说话"
                actionTitle = ""
                canRetry = false
                applySpeechReadiness(.terminated(.recordingTooShort))
                setProcessingFeedback(.failed, text: "录音过短，已终止")
                refreshFoundationModelAvailability()
                pipeline.resetToIdle()
                self.activeSessionId = nil
                return
            }
            stateText = "Failed"
            if let voxError = error as? VoxErrorCode, voxError == .timeout {
                lastError = "处理超时，请重试"
                setProcessingFeedback(.failed, text: "处理超时")
            } else if let voxError = error as? VoxErrorCode, voxError == .retryExhausted {
                lastError = "处理失败（重试耗尽），请查看日志定位阶段"
                setProcessingFeedback(.failed, text: "处理失败（重试耗尽）")
            } else {
                lastError = "处理失败，请重试"
                setProcessingFeedback(.failed)
            }
            updateModelStatusForError(error)
            actionTitle = "重试本次"
            canRetry = true
            refreshFoundationModelAvailability()
            pipeline.resetToIdle()
            self.activeSessionId = nil
        }
    }

    private func missingPermissionItem() -> PermissionItem {
        if !permissionSnapshot.microphoneGranted { return .microphone }
        if !permissionSnapshot.accessibilityGranted { return .accessibility }
        return .speechRecognition
    }

    private func recordMetricSummary() {
        if let p50 = pipeline.percentileLatency(0.5), let p95 = pipeline.percentileLatency(0.95) {
            sceneHint = "当前时延 P50 \(p50)ms / P95 \(p95)ms"
        }
        let resource = performanceSampler.sample()
        resourceHint = String(format: "CPU %.1f%% / 内存 %.1fMB", resource.cpuUsagePercent, resource.memoryMB)
    }

    private func updateModelStatusForError(_ error: Error) {
        guard let voxError = error as? VoxErrorCode else {
            applySpeechReadiness(.unavailable(.unavailable))
            return
        }
        switch voxError {
        case .permissionSpeechDenied, .transcriptionUnavailable:
            applySpeechReadiness(.unavailable(.permissionRequired))
        case .retryExhausted, .timeout:
            applySpeechReadiness(.unavailable(.unavailable))
        case .cleaningUnavailable:
            applySpeechReadiness(.ready)
        case .injectionFailed:
            applySpeechReadiness(.ready)
        default:
            applySpeechReadiness(.notReady)
        }
    }

    private func refreshFoundationModelAvailability() {
        let state = foundationModelAvailabilityProvider.foundationModelAvailability()
        foundationModelAvailability = state
        applyFoundationModelReadiness(Self.foundationModelReadiness(from: state))
    }

    private func refreshModelNames() {
        let sttSetting = appSettings.speechModel
        if sttSetting.useRemote, sttSetting.provider.supportsSTT {
            let model = sttSetting.selectedSTTModel.isEmpty
                ? sttSetting.provider.sttModelPresets.first ?? "whisper-large-v3"
                : sttSetting.selectedSTTModel
            sttModelName = "\(sttSetting.provider.displayName) (\(model))"
        } else {
            sttModelName = "端侧语音识别"
        }
        
        let llmSetting = appSettings.llmModel
        if llmSetting.useRemote {
            let model = llmSetting.selectedLLMModel.isEmpty
                ? llmSetting.provider.llmModelPresets.first ?? "deepseek-chat"
                : llmSetting.selectedLLMModel
            llmModelName = "\(llmSetting.provider.displayName) (\(model))"
        } else {
            llmModelName = "Apple Foundation Model"
        }
    }

    private func fallbackMessage(for result: CleanResult) -> String {
        if result.styleTag == "仅转录" {
            return "清洗模型不可用，已降级为仅转录"
        }
        return "清洗模型不可用，已降级为规则清洗"
    }

    static func foundationModelReadiness(from state: FoundationModelAvailabilityState) -> FoundationModelReadinessState {
        switch state {
        case .available:
            return .ready
        case .modelNotReady:
            return .notReady(.modelLoading)
        case .appleIntelligenceNotEnabled:
            return .unavailable(.appleIntelligenceDisabled)
        case .deviceNotEligible:
            return .terminated(.deviceNotEligible)
        case .unavailable:
            return .unavailable(.unavailable)
        }
    }

    private func applySpeechReadiness(_ readiness: SpeechReadinessState) {
        speechReadiness = readiness
        speechStatus = readiness.statusText
    }

    private func configurePipelineObserver() {
        pipeline.stageObserver = { [weak self] event in
            self?.handlePipelineStageEvent(event)
        }
    }

    private func handlePipelineStageEvent(_ event: VoicePipeline.StageEvent) {
        guard event.phase == .started else { return }
        switch event.stage {
        case .assetCheck, .assetInstall, .analyzerCreate, .analyzerWarmup:
            setProcessingFeedback(.preparing)
        case .transcribe:
            setProcessingFeedback(.transcribing)
        case .clean:
            setProcessingFeedback(.cleaning)
        case .inject:
            setProcessingFeedback(.injecting)
        }
    }

    private func setProcessingFeedback(_ state: ProcessingFeedbackState, text: String? = nil) {
        processingFeedbackState = state
        processingFeedbackText = text ?? state.defaultText
        if state == .idle {
            if resourceHint == processingFeedbackText {
                resourceHint = ""
            }
            return
        }
        resourceHint = processingFeedbackText
    }

    private func applyFoundationModelReadiness(_ readiness: FoundationModelReadinessState) {
        foundationModelReadiness = readiness
        foundationModelStatus = readiness.statusText
    }

    private func appendHistory(from result: ProcessResult) {
        let skillId = resolveSkillId(for: result.context)
        let skillName = skillSnapshot.profiles.first(where: { $0.id == skillId })?.name ?? "默认技能"
        let appName = appNameForBundleId(result.context.bundleId)
        let item = TranscriptHistoryItem(
            appName: appName,
            bundleId: result.context.bundleId,
            skillId: skillId,
            skillName: skillName,
            sourceText: result.transcript.text,
            outputText: result.clean.cleanText,
            succeeded: result.inject.success
        )
        historyItems.insert(item, at: 0)
        if historyItems.count > appSettings.historyLimit {
            historyItems = Array(historyItems.prefix(appSettings.historyLimit))
        }
        historyStore.saveHistory(historyItems)
    }

    private func resolveSkillId(for context: ContextInfo) -> String {
        skillMatcher.resolveSkillId(
            bundleId: context.bundleId,
            category: context.appCategory,
            matching: skillSnapshot.matching
        )
    }

    private func appNameForBundleId(_ bundleId: String) -> String {
        bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }

    private func updateMenuBarSummary() {
        guard appSettings.showRecentSummary else {
            menuBarSummary = ""
            return
        }
        let text = historyItems.first?.outputText ?? ""
        if text.count <= appSettings.summaryMaxLength {
            menuBarSummary = text
        } else {
            let prefix = text.prefix(max(0, appSettings.summaryMaxLength))
            menuBarSummary = "\(prefix)…"
        }
    }

    private func saveSkills() {
        skillStore.saveSkills(skillSnapshot)
    }

    private func saveSettings() {
        settingsStore.saveSettings(appSettings)
    }
}
public enum VoxLiteFeatureBootstrap {
    static var onDeviceSpeechAvailable: Bool {
        if #available(macOS 26.0, iOS 26.0, *) {
            true
        } else {
            false
        }
    }

    @MainActor
    static func makeTranscriber(
        settings: AppSettings,
        keychain: KeychainStoring,
        logger: LoggerServing,
        performanceSampler: PerformanceSampler? = nil,
        onDeviceSpeechAvailable: Bool = VoxLiteFeatureBootstrap.onDeviceSpeechAvailable
    ) -> (transcriber: any SpeechTranscribing, usesRemoteSTT: Bool) {
        if settings.speechModel.useRemote,
           settings.speechModel.provider.supportsSTT,
           let endpoint = settings.speechModel.effectiveEndpoint {
            if #available(macOS 26.0, iOS 26.0, *) {
                do {
                    let apiKey = try keychain.retrieve(forKey: settings.speechModel.provider.rawValue)
                    if let apiKey = apiKey {
                        let client = OpenAIClient(baseURL: endpoint, apiKey: apiKey, logger: logger)
                        let model = settings.speechModel.selectedSTTModel.isEmpty
                            ? settings.speechModel.provider.sttModelPresets.first ?? "whisper-large-v3"
                            : settings.speechModel.selectedSTTModel
                        logger.info("bootstrap using remote stt provider=\(settings.speechModel.provider.displayName) model=\(model)")
                        let transcriber = RemoteSpeechTranscriber(client: client, model: model, logger: logger)
                        return (transcriber, true)
                    }
                    logger.warn("bootstrap stt api key not found for provider=\(settings.speechModel.provider.displayName), falling back to on-device")
                } catch {
                    logger.warn("bootstrap stt keychain error=\(error.localizedDescription), falling back to on-device")
                }
            } else {
                logger.warn("bootstrap remote stt unavailable on current platform, falling back to compatibility transcriber")
            }
        }
        if onDeviceSpeechAvailable {
            if #available(macOS 26.0, iOS 26.0, *) {
                let policy = ModelRetentionPolicy(deviceTier: DeviceTierDetector.detect())
                return (OnDeviceSpeechTranscriber(logger: logger, performanceSampler: performanceSampler, retentionPolicy: policy), false)
            }
        }
        logger.warn("bootstrap on-device transcriber unavailable on current platform, using compatibility fallback")
        return (UnsupportedPlatformSpeechTranscriber(logger: logger), false)
    }

    @MainActor
    private static func buildRuntimeChain(
        settingsStore: AppSettingsStore,
        skillStore: SkillStore,
        keychain: KeychainStoring,
        permissions: PermissionManaging,
        logger: LoggerServing,
        metrics: MetricsServing,
        performanceSampler: PerformanceSampler? = nil
    ) -> (pipeline: VoicePipeline, availabilityProvider: any FoundationModelAvailabilityProviding) {
        let settings = settingsStore.loadSettings()
        let stateMachine = VoxStateMachine()
        let audio = AudioCaptureService(logger: logger)
        var usesRemoteLLM = false

        let transcriberSelection = makeTranscriber(settings: settings, keychain: keychain, logger: logger, performanceSampler: performanceSampler)
        let transcriber = transcriberSelection.transcriber
        let usesRemoteSTT = transcriberSelection.usesRemoteSTT

        let generator: PromptGenerating
        if settings.llmModel.useRemote {
            if let endpoint = settings.llmModel.effectiveEndpoint {
                do {
                    let apiKey = try keychain.retrieve(forKey: settings.llmModel.provider.rawValue)
                    if let apiKey = apiKey {
                        let client = OpenAIClient(baseURL: endpoint, apiKey: apiKey, logger: logger)
                        let model = settings.llmModel.selectedLLMModel.isEmpty
                            ? settings.llmModel.provider.llmModelPresets.first ?? "deepseek-chat"
                            : settings.llmModel.selectedLLMModel
                        generator = RemoteLLMGenerator(client: client, model: model, logger: logger)
                        usesRemoteLLM = true
                        logger.info("bootstrap using remote llm provider=\(settings.llmModel.provider.displayName) model=\(model)")
                    } else {
                        logger.warn("bootstrap llm api key not found for provider=\(settings.llmModel.provider.displayName), falling back to foundation model")
                        generator = FoundationModelPromptGenerator()
                    }
                } catch {
                    logger.warn("bootstrap llm keychain error=\(error.localizedDescription), falling back to foundation model")
                    generator = FoundationModelPromptGenerator()
                }
            } else {
                logger.warn("bootstrap llm no effective endpoint for provider=\(settings.llmModel.provider.displayName), falling back to foundation model")
                generator = FoundationModelPromptGenerator()
            }
        } else {
            generator = FoundationModelPromptGenerator()
        }

        let resolver = FrontmostContextResolver()
        let cleaner = RuleBasedTextCleaner(skillStore: skillStore, matcher: SkillMatcher(), generator: generator)
        let injector = ClipboardTextInjector(logger: logger)
        let retryPolicy = (usesRemoteSTT || usesRemoteLLM) ? RetryPolicy.remoteModelDefault : .m2Default
        let pipeline = VoicePipeline(
            stateMachine: stateMachine,
            audioCapture: audio,
            transcriber: transcriber,
            contextResolver: resolver,
            cleaner: cleaner,
            injector: injector,
            permissions: permissions,
            logger: logger,
            metrics: metrics,
            retryPolicy: retryPolicy
        )
        return (pipeline, cleaner)
    }

    @MainActor
    public static func makeDefaultViewModel(
        historyStore: HistoryStore = FileHistoryStore(),
        skillStore: SkillStore = FileSkillStore(),
        settingsStore: AppSettingsStore = FileAppSettingsStore(),
        launchAtLoginManager: LaunchAtLoginManaging = UserDefaultsLaunchAtLoginManager(),
        keychain: KeychainStoring = KeychainStorage(),
        permissions: PermissionManaging = PermissionManager(),
        performanceSampler: PerformanceSampler = PerformanceSampler()
    ) -> AppViewModel {
        let logger = ConsoleLogger()
        let metrics = InMemoryMetrics()
        let runtimeChain = buildRuntimeChain(
            settingsStore: settingsStore,
            skillStore: skillStore,
            keychain: keychain,
            permissions: permissions,
            logger: logger,
            metrics: metrics,
            performanceSampler: performanceSampler
        )

        let viewModel = AppViewModel(
            pipeline: runtimeChain.pipeline,
            permissions: permissions,
            performanceSampler: performanceSampler,
            historyStore: historyStore,
            skillStore: skillStore,
            settingsStore: settingsStore,
            launchAtLoginManager: launchAtLoginManager,
            foundationModelAvailabilityProvider: runtimeChain.availabilityProvider,
            runtimeChainReloader: {
                buildRuntimeChain(
                    settingsStore: settingsStore,
                    skillStore: skillStore,
                    keychain: keychain,
                    permissions: permissions,
                    logger: logger,
                    metrics: metrics,
                    performanceSampler: performanceSampler
                )
            }
        )
        
        viewModel.onReleaseResources = { [weak viewModel] in
            await viewModel?.resetResources()
        }
        
        return viewModel
    }
}
