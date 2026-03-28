import AppKit
import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain

@MainActor
struct ContextResolverTests {
    @Test
    func contextInfo_whenUsingLegacyInitializer_keepsStablePrimaryFields() {
        let context = ContextInfo(
            bundleId: "com.test.legacy",
            appCategory: .general,
            inputRole: "textField",
            locale: "zh_CN"
        )

        #expect(context.bundleId == "com.test.legacy")
        #expect(context.appCategory == .general)
        #expect(context.inputRole == "textField")
        #expect(context.locale == "zh_CN")
        #expect(context.enrich == nil)
    }

    @Test
    func buildEnrichment_whenBundleInferenceSucceeds_returnsOptionalEnrichWithoutChangingPrimaryKeys() {
        let resolver = FrontmostContextResolver()

        let enrich = resolver.buildEnrichment(for: nil, bundleId: "com.apple.dt.Xcode", category: .development)

        #expect(enrich?.appName == nil)
        #expect(enrich?.isEditable == true)
        #expect(enrich?.focusedRole == "sourceEditor")
        #expect(enrich?.vocabularyBias["cmd"] == "command")
        #expect(enrich?.vocabularyBias["api"] == "API")
    }

    @Test
    func buildEnrichment_whenInferenceIsWeak_fallsBackToCoarseCategoryOnly() {
        let resolver = FrontmostContextResolver()

        let enrich = resolver.buildEnrichment(for: nil, bundleId: "unknown", category: .general)

        #expect(enrich == nil)
    }

    @Test
    func cleaner_whenEnrichMissing_usesLegacyFallbackBehaviorSafely() async {
        let cleaner = RuleBasedTextCleaner(generator: ContextResolverFailingPromptGenerator())
        let context = ContextInfo(
            bundleId: "com.slack",
            appCategory: .communication,
            inputRole: "textField",
            locale: "zh_CN"
        )

        let result = await cleaner.cleanText(transcript: "嗯 今晚完成接口对齐", context: context)

        #expect(result.success)
        #expect(result.usedFallback)
        #expect(result.cleanText == "今晚完成接口对齐。")
    }

    @Test
    func cleaner_whenEnrichProvidesBiasAndNonEditable_appliesSoftConsumptionWithoutHardDependency() async {
        let cleaner = RuleBasedTextCleaner(generator: ContextResolverCapturingPromptGenerator(output: "command add fallback path。"))
        let context = ContextInfo(
            bundleId: "com.apple.finder",
            appCategory: .general,
            inputRole: "textField",
            locale: "zh_CN",
            enrich: ContextEnrichment(
                appName: "Finder",
                isEditable: false,
                focusedRole: "list",
                vocabularyBias: ["cmd": "command"]
            )
        )

        let result = await cleaner.cleanText(transcript: "cmd add fallback path", context: context)

        #expect(result.success)
        #expect(result.cleanText.contains("command"))
        #expect(result.cleanText.contains("。") == false)
    }

    @Test
    func cleaner_whenPromptPathUsesEnrich_includesOptionalHintsButStillProducesOutput() async {
        let generator = ContextResolverCapturingPromptGenerator(output: "command add fallback path。")
        let cleaner = RuleBasedTextCleaner(
            skillStore: TestSkillStore(),
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

        let result = await cleaner.cleanText(transcript: "cmd add fallback path", context: context)

        #expect(result.success)
        #expect(result.cleanText == "command add fallback path。")
        #expect(generator.prompts.count == 1)
        #expect(generator.prompts[0].contains("当前应用：Xcode。"))
        #expect(generator.prompts[0].contains("焦点角色：sourceEditor。"))
        #expect(generator.prompts[0].contains("词汇偏置：优先使用以下写法：cmd→command。"))
        #expect(generator.prompts[0].contains("command add fallback path"))
    }
}

private struct ContextResolverFailingPromptGenerator: PromptGenerating {
    func generateText(from prompt: String) async throws -> String {
        throw PromptGenerationError.unavailable
    }

    func availabilityState() -> FoundationModelAvailabilityState {
        .available
    }
}

private final class ContextResolverCapturingPromptGenerator: PromptGenerating {
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
