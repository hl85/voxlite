import Foundation
import Testing
@testable import VoxLiteDomain
@testable import VoxLiteFeature
@testable import VoxLiteSystem

@MainActor
struct StreamingModeTests {
    private let defaultsKey = "streamingMode"

    @Test
    func testDefaultModeIsOff() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        let viewModel = makeViewModel()

        #expect(viewModel.streamingMode == .off)
    }

    @Test
    func testModePersistence() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        let viewModel = makeViewModel()
        viewModel.streamingMode = .previewOnly
        #expect(viewModel.streamingMode == .previewOnly)

        #expect(UserDefaults.standard.string(forKey: defaultsKey) == StreamingMode.previewOnly.rawValue)

        let reloaded = makeViewModel()
        #expect(reloaded.streamingMode == .previewOnly)
    }

    @Test
    func testModeSwitch() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        let viewModel = makeViewModel()

        viewModel.streamingMode = .previewOnly
        #expect(viewModel.streamingMode == .previewOnly)

        viewModel.streamingMode = .full
        #expect(viewModel.streamingMode == .full)

        viewModel.streamingMode = .off
        #expect(viewModel.streamingMode == .off)
    }

    @Test
    func testModeChangeDoesNotTriggerRecording() async {
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        let viewModel = makeViewModel()
        let before = viewModel.stateText

        viewModel.streamingMode = .previewOnly
        viewModel.streamingMode = .full

        #expect(viewModel.stateText == before)
        #expect(viewModel.stateText == "Idle")
    }

    private func makeViewModel() -> AppViewModel {
        let permissions = TestPermissions()
        let (pipeline, _, _, _, _) = makePipeline(permissions: permissions)
        return AppViewModel(
            pipeline: pipeline,
            permissions: permissions,
            performanceSampler: PerformanceSampler(),
            historyStore: TestHistoryStore(),
            skillStore: TestSkillStore(),
            settingsStore: TestSettingsStore(),
            launchAtLoginManager: TestLaunchAtLoginManager(),
            foundationModelAvailabilityProvider: TestAvailabilityProvider()
        )
    }
}
