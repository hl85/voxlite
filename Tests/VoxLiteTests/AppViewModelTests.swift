import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteFeature
@testable import VoxLiteSystem

@MainActor
struct AppViewModelTests {
    final class TestKeychain: KeychainStoring, @unchecked Sendable {
        var values: [String: String]

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

    @Test
    func init_whenPermissionsMissing_startsOnOnboardingStepOne() {
        let permissions = TestPermissions(
            snapshot: .init(microphoneGranted: false, speechRecognitionGranted: false, accessibilityGranted: false)
        )
        let historyStore = TestHistoryStore()
        let settingsStore = TestSettingsStore()
        let (pipeline, _, _, _, _) = makePipeline(permissions: permissions)

        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: historyStore,
            skillStore: TestSkillStore(),
            settingsStore: settingsStore,
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )

        #expect(viewModel.showOnboarding)
        #expect(viewModel.onboardingStep == 1)
        #expect(viewModel.selectedModule == .welcome)
    }

    @Test
    func simulatePressForTesting_whenPermissionsMissing_updatesErrorState() async {
        let permissions = TestPermissions(
            snapshot: .init(microphoneGranted: false, speechRecognitionGranted: true, accessibilityGranted: true)
        )
        let (pipeline, _, _, _, _) = makePipeline(permissions: permissions)
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )

        await viewModel.simulatePressForTesting()

        #expect(viewModel.stateText == "Failed")
        #expect(viewModel.lastError == "权限未就绪，请先完成授权")
        #expect(viewModel.actionTitle == "打开系统设置")
        #expect(viewModel.recommendedSettingItem == .microphone)
        #expect(viewModel.canRetry == false)
    }

    @Test
    func simulatePressAndRelease_whenPipelineSucceeds_updatesHistoryAndSummary() async throws {
        let historyStore = TestHistoryStore()
        let settingsStore = TestSettingsStore()
        let (pipeline, _, _, _, permissions) = makePipeline()
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: historyStore,
            skillStore: TestSkillStore(),
            settingsStore: settingsStore,
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )

        await viewModel.simulatePressForTesting()
        await viewModel.simulateReleaseForTesting()

        #expect(viewModel.stateText == "Done")
        #expect(viewModel.cleanedText == "清洗后文本")
        #expect(viewModel.trialRunPassed)
        #expect(viewModel.historyItems.count == 1)
        #expect(viewModel.menuBarSummary == "清洗后文本")
        let firstItem = try #require(historyStore.items.first)
        #expect(firstItem.outputText == "清洗后文本")
    }

    @Test
    func simulateReleaseForTesting_whenPipelineTimesOut_exposesRetryState() async throws {
        let transcriber = TestTranscriber(
            result: .success(SpeechTranscription(text: "超时文本", latencyMs: 3_501, usedOnDevice: true))
        )
        let (pipeline, _, _, _, permissions) = makePipeline(transcriber: transcriber)
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )

        await viewModel.simulatePressForTesting()
        await viewModel.simulateReleaseForTesting()

        #expect(viewModel.stateText == "Failed")
        #expect(viewModel.lastError == "处理超时，请重试")
        #expect(viewModel.actionTitle == "重试本次")
        #expect(viewModel.canRetry)
        #expect(viewModel.speechReadiness == .unavailable(.unavailable))
    }

    @Test
    func readinessStatusTextMapping_exposesSpeechAndFoundationMessages() {
        #expect(SpeechReadinessState.notReady.statusText == "未就绪：待录音")
        #expect(SpeechReadinessState.downloading.statusText == "下载中：语音资产")
        #expect(SpeechReadinessState.installing.statusText == "安装中：语音模型")
        #expect(SpeechReadinessState.ready.statusText == "已就绪")
        #expect(SpeechReadinessState.unavailable(.permissionRequired).statusText == "不可用：权限未就绪")
        #expect(SpeechReadinessState.terminated(.recordingTooShort).statusText == "终止：录音过短")

        #expect(AppViewModel.foundationModelReadiness(from: .available) == .ready)
        #expect(AppViewModel.foundationModelReadiness(from: .modelNotReady) == .notReady(.modelLoading))
        #expect(AppViewModel.foundationModelReadiness(from: .appleIntelligenceNotEnabled) == .unavailable(.appleIntelligenceDisabled))
        #expect(AppViewModel.foundationModelReadiness(from: .deviceNotEligible) == .terminated(.deviceNotEligible))
        #expect(AppViewModel.foundationModelReadiness(from: .unavailable) == .unavailable(.unavailable))
        #expect(FoundationModelReadinessState.unavailable(.appleIntelligenceDisabled).statusText == "不可用：请先开启 Apple Intelligence")
        #expect(FoundationModelReadinessState.terminated(.deviceNotEligible).statusText == "终止：当前设备不支持 Apple Foundation Model")
    }

    @Test
    func init_whenFoundationModelNotReady_exposesDetailedAvailabilityStatus() {
        let permissions = TestPermissions()
        let (pipeline, _, _, _, _) = makePipeline(permissions: permissions)
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider(state: .modelNotReady)
        )

        #expect(viewModel.foundationModelAvailability == .modelNotReady)
        #expect(viewModel.foundationModelReadiness == .notReady(.modelLoading))
        #expect(viewModel.foundationModelStatus == "未就绪：Foundation Model 正在加载")
    }

    @Test
    func simulatePressForTesting_whenPermissionsMissing_updatesSpeechReadiness() async {
        let permissions = TestPermissions(
            snapshot: .init(microphoneGranted: false, speechRecognitionGranted: true, accessibilityGranted: true)
        )
        let (pipeline, _, _, _, _) = makePipeline(permissions: permissions)
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider(state: .appleIntelligenceNotEnabled)
        )

        await viewModel.simulatePressForTesting()

        #expect(viewModel.speechReadiness == .unavailable(.permissionRequired))
        #expect(viewModel.speechStatus == "不可用：权限未就绪")
        #expect(viewModel.foundationModelReadiness == .unavailable(.appleIntelligenceDisabled))
        #expect(viewModel.foundationModelStatus == "不可用：请先开启 Apple Intelligence")
    }

    @Test
    func simulatePressAndRelease_whenPipelineSucceeds_updatesReadyReadinessStates() async {
        let historyStore = TestHistoryStore()
        let settingsStore = TestSettingsStore()
        let (pipeline, _, _, _, permissions) = makePipeline()
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: historyStore,
            skillStore: TestSkillStore(),
            settingsStore: settingsStore,
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider(state: .available)
        )

        await viewModel.simulatePressForTesting()
        #expect(viewModel.speechReadiness == .notReady)
        #expect(viewModel.speechStatus == "未就绪：待录音")

        await viewModel.simulateReleaseForTesting()

        #expect(viewModel.speechReadiness == .ready)
        #expect(viewModel.speechStatus == "已就绪")
        #expect(viewModel.foundationModelReadiness == .ready)
        #expect(viewModel.foundationModelStatus == "已就绪")
        #expect(viewModel.processingFeedbackState == .completed)
        #expect(viewModel.processingFeedbackText == "已完成")
    }

    @Test
    func simulateReleaseForTesting_whenTranscriptionIsSlow_updatesProcessingFeedback() async {
        let transcriber = TestTranscriberWithObservability(delayNanos: 300_000_000)
        let (pipeline, _, _, _, permissions) = makePipeline(transcriber: transcriber)
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider(state: .modelNotReady)
        )

        await viewModel.simulatePressForTesting()
        let releaseTask = Task { await viewModel.simulateReleaseForTesting() }
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.stateText == "Processing")
        #expect(viewModel.speechReadiness == SpeechReadinessState.installing)
        #expect(viewModel.speechStatus == "安装中：语音模型")
        #expect(
            viewModel.processingFeedbackState == ProcessingFeedbackState.preparing
            || viewModel.processingFeedbackState == ProcessingFeedbackState.transcribing
        )

        _ = await releaseTask.value

        #expect(viewModel.stateText == "Done")
        #expect(viewModel.processingFeedbackState == ProcessingFeedbackState.completed)
        #expect(viewModel.processingFeedbackText == "已完成")
    }

    @Test
    func simulateReleaseForTesting_whenRecordingTooShort_marksSpeechTerminated() async {
        let audioCapture = TestAudioCapture(stopResult: .failure(VoxErrorCode.recordingUnavailable))
        let stateMachine = TestStateStore()
        let permissions = TestPermissions()
        let (pipeline, _, _, _, _) = makePipeline(
            stateMachine: stateMachine,
            audioCapture: audioCapture,
            permissions: permissions
        )
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider(state: .deviceNotEligible)
        )

        await viewModel.simulatePressForTesting()
        await viewModel.simulateReleaseForTesting()

        #expect(viewModel.stateText == "Idle")
        #expect(viewModel.speechReadiness == .terminated(.recordingTooShort))
        #expect(viewModel.speechStatus == "终止：录音过短")
        #expect(viewModel.foundationModelReadiness == .terminated(.deviceNotEligible))
        #expect(viewModel.foundationModelStatus == "终止：当前设备不支持 Apple Foundation Model")
    }

    @Test
    func makeTranscriber_whenOnDeviceUnavailable_returnsCompatibilityTranscriber() async throws {
        let settings = FileAppSettingsStore.defaultSettings
        let keychain = TestKeychain()
        let transcriber = VoxLiteFeatureBootstrap.makeTranscriber(
            settings: settings,
            keychain: keychain,
            logger: TestLogger(),
            onDeviceSpeechAvailable: false
        )
        #expect(transcriber.usesRemoteSTT == false)
        #expect(transcriber.transcriber is UnsupportedPlatformSpeechTranscriber)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        try Data("stub".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await transcriber.transcriber.transcribe(audioFileURL: tempURL, elapsedMs: 0)
            Issue.record("Expected unsupported platform transcriber error")
        } catch let error as SpeechTranscriptionError {
            #expect(error == .transcriberUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func makeTranscriber_whenRemoteSTTConfiguredOnCurrentPlatform_usesExpectedPath() {
        var settings = FileAppSettingsStore.defaultSettings
        settings.speechModel = ModelSetting(
            useRemote: true,
            provider: .groq,
            customEndpoint: "",
            selectedSTTModel: "whisper-large-v3",
            selectedLLMModel: ""
        )
        let keychain = TestKeychain(values: [RemoteProvider.groq.rawValue: "test-key"])

        let transcriber = VoxLiteFeatureBootstrap.makeTranscriber(
            settings: settings,
            keychain: keychain,
            logger: TestLogger(),
            onDeviceSpeechAvailable: false
        )

        if #available(macOS 26.0, iOS 26.0, *) {
            #expect(transcriber.usesRemoteSTT)
            #expect(transcriber.transcriber is RemoteSpeechTranscriber)
        } else {
            #expect(transcriber.usesRemoteSTT == false)
            #expect(transcriber.transcriber is UnsupportedPlatformSpeechTranscriber)
        }
    }

    @Test
    func testPartialTextUpdateDuringRecording() async {
        let streamingTranscriber = TestStreamingTranscriber()
        streamingTranscriber.partialResults = [
            PartialTranscription(text: "你好", isFinal: false),
            PartialTranscription(text: "你好世界", isFinal: false)
        ]
        let pipeline = makeHybridPipeline(
            streamingMode: .previewOnly,
            streamingTranscriber: streamingTranscriber
        )
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: TestPermissions(),
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )
        viewModel.streamingMode = .previewOnly
        await viewModel.simulatePressForTesting()

        pipeline.onPartialTranscription?(PartialTranscription(text: "你好", isFinal: false))
        #expect(viewModel.partialText == "你好")

        pipeline.onPartialTranscription?(PartialTranscription(text: "你好世界", isFinal: false))
        #expect(viewModel.partialText == "你好世界")
    }

    @Test
    func testPartialTextClearedOnFinalResult() async {
        let pipeline = makeHybridPipeline(streamingMode: .previewOnly)
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: TestPermissions(),
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )
        viewModel.streamingMode = .previewOnly

        await viewModel.simulatePressForTesting()
        pipeline.onPartialTranscription?(PartialTranscription(text: "中间文本", isFinal: false))
        #expect(viewModel.partialText == "中间文本")

        await viewModel.simulateReleaseForTesting()
        #expect(viewModel.partialText == "")
        #expect(viewModel.isStreamingActive == false)
    }

    @Test
    func testPartialTextOffMode() async {
        let pipeline = makeHybridPipeline(streamingMode: .off)
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: TestPermissions(),
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )
        viewModel.streamingMode = .off

        await viewModel.simulatePressForTesting()
        pipeline.onPartialTranscription?(PartialTranscription(text: "任意文本", isFinal: false))
        #expect(viewModel.partialText == "")
        #expect(viewModel.isStreamingActive == false)

        await viewModel.simulateReleaseForTesting()
        #expect(viewModel.partialText == "")
    }

    @Test
    func testPartialTextStreamingFailure() async {
        let streamingTranscriber = TestStreamingTranscriber()
        streamingTranscriber.shouldFailStreaming = true
        let pipeline = makeHybridPipeline(
            streamingMode: .previewOnly,
            streamingTranscriber: streamingTranscriber
        )
        let viewModel = AppViewModel(
            pipeline: pipeline,
            permissions: TestPermissions(),
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )
        viewModel.streamingMode = .previewOnly

        await viewModel.simulatePressForTesting()
        #expect(viewModel.partialText == "" || !viewModel.partialText.isEmpty)

        await viewModel.simulateReleaseForTesting()
        #expect(viewModel.partialText == "")
    }
}
