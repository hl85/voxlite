import Foundation
import VoxLiteCore
import VoxLiteDomain
import VoxLiteInput
import VoxLiteOutput
import VoxLiteSystem

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

    private let pipeline: VoicePipeline
    private let permissions: PermissionManaging
    private let performanceSampler: PerformanceSampler
    private var monitor: HotKeyMonitor?
    private var activeSessionId: UUID?

    public init(pipeline: VoicePipeline, permissions: PermissionManaging, performanceSampler: PerformanceSampler) {
        self.pipeline = pipeline
        self.permissions = permissions
        self.performanceSampler = performanceSampler
        self.permissionSnapshot = permissions.currentPermissionSnapshot()
        self.showOnboarding = !permissionSnapshot.allGranted
        self.onboardingStep = showOnboarding ? 1 : 4
        configureMonitor()
    }

    public func startMonitor() {
        if !showOnboarding {
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

    public func skipOnboarding() {
        onboardingStep = 4
        showOnboarding = false
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

    public func retryLatest() async {
        guard canRetry else { return }
        lastError = "请按住快捷键重新录入"
        actionTitle = ""
        canRetry = false
        stateText = "Idle"
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
    }

    private func updateOnboardingStep() {
        if !permissionSnapshot.microphoneGranted {
            onboardingStep = 1
        } else if !permissionSnapshot.accessibilityGranted {
            onboardingStep = 2
        } else if !permissionSnapshot.speechRecognitionGranted {
            onboardingStep = 3
        } else {
            onboardingStep = 4
            showOnboarding = false
            startMonitor()
        }
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
        cleanedText = ""
        activeSessionId = nil
        canRetry = false
        actionTitle = ""
    }

    private func handlePress() async {
        permissionSnapshot = permissions.currentPermissionSnapshot()
        speechStatus = "待录音"
        foundationModelStatus = "待处理"
        guard permissionSnapshot.allGranted else {
            stateText = "Failed"
            showOnboarding = true
            updateOnboardingStep()
            lastError = "权限未就绪，请先完成授权"
            actionTitle = "打开系统设置"
            recommendedSettingItem = missingPermissionItem()
            canRetry = false
            return
        }
        do {
            let sessionId = try pipeline.startRecording()
            activeSessionId = sessionId
            stateText = "Recording"
            lastError = ""
            actionTitle = ""
            recommendedSettingItem = nil
            canRetry = false
            showRecordingAnimation = true
        } catch {
            if let voxError = error as? VoxErrorCode, voxError == .recordingUnavailable {
                stateText = "Idle"
                lastError = "录音设备忙碌或触发过快，请稍后重试"
                actionTitle = ""
                recommendedSettingItem = nil
                canRetry = false
                speechStatus = "录音不可用"
                foundationModelStatus = "待处理"
                return
            }
            stateText = "Failed"
            lastError = "权限或录音不可用"
            actionTitle = "打开系统设置"
            recommendedSettingItem = .microphone
            canRetry = false
            speechStatus = "异常"
            foundationModelStatus = "待处理"
        }
    }

    private func handleRelease() async {
        guard let activeSessionId else { return }
        showRecordingAnimation = false
        do {
            stateText = "Processing"
            let result = try await pipeline.stopRecordingAndProcess(sessionId: activeSessionId)
            stateText = result.inject.success ? "Done" : "Failed"
            cleanedText = result.clean.cleanText
            speechStatus = result.transcript.success ? "正常（端侧）" : "异常"
            foundationModelStatus = result.clean.usedFallback ? "降级（规则回退）" : "正常"
            if result.clean.usedFallback {
                lastError = "清洗模型不可用，已降级为仅转录"
                actionTitle = ""
                canRetry = false
            } else {
                lastError = result.inject.success ? "" : "注入失败，已复制到剪贴板，可按 Cmd+V 粘贴"
                actionTitle = result.inject.success ? "" : "重试本次"
                canRetry = !result.inject.success
            }
            recommendedSettingItem = nil
            pipeline.resetToIdle()
            self.activeSessionId = nil
            recordMetricSummary()
        } catch {
            if let voxError = error as? VoxErrorCode, voxError == .recordingUnavailable {
                stateText = "Idle"
                lastError = "按住快捷键稍久一点再说话"
                actionTitle = ""
                canRetry = false
                speechStatus = "录音过短/不可用"
                foundationModelStatus = "待处理"
                pipeline.resetToIdle()
                self.activeSessionId = nil
                return
            }
            stateText = "Failed"
            if let voxError = error as? VoxErrorCode, voxError == .timeout {
                lastError = "处理超时，请重试"
            } else if let voxError = error as? VoxErrorCode, voxError == .retryExhausted {
                lastError = "处理失败（重试耗尽），请查看日志定位阶段"
            } else {
                lastError = "处理失败，请重试"
            }
            updateModelStatusForError(error)
            actionTitle = "重试本次"
            canRetry = true
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
            speechStatus = "异常"
            foundationModelStatus = "未知"
            return
        }
        switch voxError {
        case .permissionSpeechDenied, .transcriptionUnavailable:
            speechStatus = "异常"
            foundationModelStatus = "待处理"
        case .retryExhausted, .timeout:
            speechStatus = "异常"
            foundationModelStatus = "待处理"
        case .cleaningUnavailable:
            speechStatus = "正常"
            foundationModelStatus = "异常"
        case .injectionFailed:
            speechStatus = "正常"
            foundationModelStatus = "正常"
        default:
            speechStatus = "未知"
            foundationModelStatus = "未知"
        }
    }
}

public enum VoxLiteFeatureBootstrap {
    @MainActor
    public static func makeDefaultViewModel() -> AppViewModel {
        let logger = ConsoleLogger()
        let metrics = InMemoryMetrics()
        let stateMachine = VoxStateMachine()
        let permissions = PermissionManager()
        let audio = AudioCaptureService(logger: logger)
        let transcriber: SpeechTranscribing
        if #available(macOS 26.0, iOS 26.0, *) {
            transcriber = OnDeviceSpeechTranscriber(logger: logger)
        } else {
            fatalError("OnDeviceSpeechTranscriber requires macOS 26+ / iOS 26+")
        }
        let resolver = FrontmostContextResolver()
        let cleaner = RuleBasedTextCleaner()
        let injector = ClipboardTextInjector(logger: logger)
        let performanceSampler = PerformanceSampler()

        let pipeline = VoicePipeline(
            stateMachine: stateMachine,
            audioCapture: audio,
            transcriber: transcriber,
            contextResolver: resolver,
            cleaner: cleaner,
            injector: injector,
            permissions: permissions,
            logger: logger,
            metrics: metrics
        )

        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: performanceSampler
        )
        return viewModel
    }
}
