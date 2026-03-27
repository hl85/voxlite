import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteFeature
@testable import VoxLiteSystem

@MainActor
struct AppViewModelTests {
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
    }
}
