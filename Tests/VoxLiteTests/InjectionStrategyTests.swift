import Testing
@testable import VoxLiteDomain
@testable import VoxLiteOutput

struct InjectionStrategyTests {
    struct ConfigurableInjector: TextInjecting {
        let result: InjectResult
        func injectText(_ text: String) -> InjectResult { result }
    }

    @Test
    func singleStrategy_success_returnsSuccess() {
        let chain = InjectionStrategyChain(strategies: [
            ConfigurableInjector(result: InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 5))
        ])
        let result = chain.injectText("test")
        #expect(result.success)
        #expect(result.usedClipboardFallback == false)
    }

    @Test
    func singleStrategy_failure_returnsFailureWithFallback() {
        let chain = InjectionStrategyChain(strategies: [
            ConfigurableInjector(result: InjectResult(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: 5))
        ])
        let result = chain.injectText("test")
        #expect(!result.success)
        #expect(result.usedClipboardFallback)
        #expect(result.errorCode == .injectionFailed)
    }

    @Test
    func multipleStrategies_firstFails_secondSucceeds() {
        let chain = InjectionStrategyChain(strategies: [
            ConfigurableInjector(result: InjectResult(success: false, usedClipboardFallback: false, errorCode: .injectionFailed, latencyMs: 5)),
            ConfigurableInjector(result: InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: 10))
        ])
        let result = chain.injectText("test")
        #expect(result.success)
    }

    @Test
    func multipleStrategies_allFail_returnsLastResult() {
        let chain = InjectionStrategyChain(strategies: [
            ConfigurableInjector(result: InjectResult(success: false, usedClipboardFallback: false, errorCode: .injectionFailed, latencyMs: 5)),
            ConfigurableInjector(result: InjectResult(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: 10))
        ])
        let result = chain.injectText("test")
        #expect(!result.success)
        #expect(result.usedClipboardFallback == true)
        #expect(result.latencyMs == 10)
    }

    @Test
    func defaultChainWithClipboard_preservesFallbackSemantics() {
        let injector = ClipboardTextInjector(
            logger: TestLogger(),
            restoreDelayNanos: 0,
            getClipboardString: { "old" },
            clearClipboard: { },
            setClipboardString: { _ in },
            pasteCommand: { false },
            scheduleRestore: { _, action in action() }
        )
        let chain = InjectionStrategyChain(strategies: [injector])
        let result = chain.injectText("new")
        #expect(!result.success)
        #expect(result.usedClipboardFallback)
        #expect(result.errorCode == .injectionFailed)
    }
}
