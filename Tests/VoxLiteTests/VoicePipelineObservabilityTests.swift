import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteFeature
@testable import VoxLiteSystem

@MainActor
struct VoicePipelineObservabilityTests {
    @Test
    func stopRecordingAndProcess_emitsGranularStageMetrics() async throws {
        let metrics = TestMetrics()
        let transcriber = TestTranscriberWithObservability()
        let (pipeline, _, _, _, permissions) = makePipeline(transcriber: transcriber, metrics: metrics)
        var observedEvents: [VoicePipeline.StageEvent] = []
        pipeline.stageObserver = { event in
            observedEvents.append(event)
        }

        let sessionId = try pipeline.startRecording()
        _ = try await pipeline.stopRecordingAndProcess(sessionId: sessionId)

        let completedStages = observedEvents
            .filter { $0.phase == .completed }
            .map(\.stage)
        #expect(completedStages.contains(.assetCheck))
        #expect(completedStages.contains(.assetInstall))
        #expect(completedStages.contains(.analyzerCreate))
        #expect(completedStages.contains(.analyzerWarmup))
        #expect(completedStages.contains(.transcribe))
        #expect(completedStages.contains(.clean))
        #expect(completedStages.contains(.inject))

        #expect(metrics.records.contains(where: { $0.event == "pipeline.stage.asset-check" && $0.success }))
        #expect(metrics.records.contains(where: { $0.event == "pipeline.stage.asset-install" && $0.success }))
        #expect(metrics.records.contains(where: { $0.event == "pipeline.stage.analyzer-create" && $0.success }))
        #expect(metrics.records.contains(where: { $0.event == "pipeline.stage.analyzer-warmup" && $0.success }))
        #expect(metrics.records.contains(where: { $0.event == "pipeline.stage.transcribe" && $0.success }))
        #expect(metrics.records.contains(where: { $0.event == "pipeline.stage.clean" && $0.success }))
        #expect(metrics.records.contains(where: { $0.event == "pipeline.stage.inject" && $0.success }))

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
        let releaseTask = Task { await viewModel.simulateReleaseForTesting() }
        try? await Task.sleep(nanoseconds: 1_000_000)
        #expect(viewModel.processingFeedbackText.isEmpty == false)
        #expect(viewModel.processingFeedbackState != .idle)
        _ = await releaseTask.value
        #expect(viewModel.processingFeedbackState == .completed)
        #expect(viewModel.processingFeedbackText == "已完成")
    }

    @Test
    func simulateReleaseForTesting_updatesProcessingFeedbackByStage() async throws {
        let transcriber = TestTranscriberWithObservability(delayNanos: 80_000_000)
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
        let releaseTask = Task { await viewModel.simulateReleaseForTesting() }

        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(viewModel.processingFeedbackState == .preparing)
        #expect(viewModel.processingFeedbackText == "准备中...")

        try? await Task.sleep(nanoseconds: 120_000_000)
        #expect(viewModel.processingFeedbackState != .idle)
        #expect(viewModel.processingFeedbackState != .preparing)

        _ = await releaseTask.value
        #expect(viewModel.processingFeedbackState == .completed)
        #expect(viewModel.processingFeedbackText == "已完成")
    }
}
