import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain

@MainActor
struct TextCleanerTests {
    @Test
    func fallbackCleaning_appliesDifferentRulesPerRoute() async {
        let cleaner = RuleBasedTextCleaner(
            skillStore: TestSkillStore(),
            matcher: SkillMatcher(),
            generator: TestFailingPromptGenerator()
        )

        let communication = await cleaner.cleanText(
            transcript: "嗯 今天先和产品对齐 然后 晚点发你确认",
            context: .init(bundleId: "com.slack", appCategory: .communication, inputRole: "textField", locale: "zh_CN")
        )
        let development = await cleaner.cleanText(
            transcript: "嗯 添加 fallbackPath 然后 修改 user_name 保留 snake_case 删除 oldEndpoint",
            context: .init(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN")
        )
        let writing = await cleaner.cleanText(
            transcript: "嗯 我觉得这个方案有点复杂，我们先这样，后面再想一下怎么落地",
            context: .init(bundleId: "com.apple.Pages", appCategory: .writing, inputRole: "textField", locale: "zh_CN")
        )

        #expect(communication.usedFallback)
        #expect(communication.cleanText == "今天先和产品对齐，晚点发你确认。")
        #expect(communication.cleanText.contains("嗯") == false)

        #expect(development.usedFallback)
        #expect(development.cleanText.contains("fallbackPath"))
        #expect(development.cleanText.contains("user_name"))
        #expect(development.cleanText.contains("snake_case"))
        #expect(development.cleanText.contains("添加"))
        #expect(development.cleanText.contains("删除"))
        #expect(development.cleanText.contains("此外") == false)
        #expect(development.cleanText.contains("进一步分析") == false)

        #expect(writing.usedFallback)
        #expect(writing.cleanText.contains("我认为"))
        #expect(writing.cleanText.contains("较为复杂"))
        #expect(writing.cleanText.contains("暂定如此"))
        #expect(writing.cleanText.contains("进一步分析"))
        #expect(writing.cleanText.contains("\n\n"))
        #expect(writing.cleanText.contains("嗯") == false)
    }

    @Test
    func llmPrompt_injectsRouteSpecificGuidanceAndNormalizedInput() async throws {
        let generator = TestCapturingPromptGenerator(output: "结果")
        let cleaner = RuleBasedTextCleaner(
            skillStore: TestSkillStore(),
            matcher: SkillMatcher(),
            generator: generator
        )

        _ = await cleaner.cleanText(
            transcript: "嗯 添加 fallbackPath 修改 user_name",
            context: .init(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN")
        )

        let prompt = try #require(generator.prompts.first)
        #expect(prompt.contains("开发路由补充要求"))
        #expect(prompt.contains("保留 camelCase、snake_case"))
        #expect(prompt.contains("用户指令：添加 fallbackPath 修改 user_name。"))
        #expect(prompt.contains("嗯") == false)
    }

    @Test
    func llmPrompt_whenCursorContextPresent_injectsSurroundingText() async throws {
        let generator = TestCapturingPromptGenerator(output: "结果")
        let cleaner = RuleBasedTextCleaner(
            skillStore: TestSkillStore(),
            matcher: SkillMatcher(),
            generator: generator
        )
        let cursorContext = CursorContext(surroundingText: "let viewModel = AppViewModel()", selectedText: nil, appBundleId: "com.apple.dt.Xcode", cursorPosition: nil)
        let enrich = ContextEnrichment(appName: "Xcode", isEditable: true, focusedRole: "textField", vocabularyBias: [:], cursorContext: cursorContext)
        let context = ContextInfo(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN", enrich: enrich)

        _ = await cleaner.cleanText(transcript: "添加 viewModel 初始化", context: context)

        let prompt = try #require(generator.prompts.first)
        #expect(prompt.contains("let viewModel = AppViewModel()"))
        #expect(prompt.contains("光标附近的文本"))
    }

    @Test
    func llmPrompt_whenCursorContextHasSelectedText_injectsSelectedText() async throws {
        let generator = TestCapturingPromptGenerator(output: "结果")
        let cleaner = RuleBasedTextCleaner(
            skillStore: TestSkillStore(),
            matcher: SkillMatcher(),
            generator: generator
        )
        let cursorContext = CursorContext(surroundingText: "func process() {}", selectedText: "process", appBundleId: "com.apple.dt.Xcode", cursorPosition: nil)
        let enrich = ContextEnrichment(appName: "Xcode", isEditable: true, focusedRole: "textField", vocabularyBias: [:], cursorContext: cursorContext)
        let context = ContextInfo(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN", enrich: enrich)

        _ = await cleaner.cleanText(transcript: "重命名方法", context: context)

        let prompt = try #require(generator.prompts.first)
        #expect(prompt.contains("process"))
        #expect(prompt.contains("选中的文本"))
    }

    @Test
    func llmPrompt_whenSurroundingTextExceeds500Chars_truncatesTo500() async throws {
        let generator = TestCapturingPromptGenerator(output: "结果")
        let cleaner = RuleBasedTextCleaner(
            skillStore: TestSkillStore(),
            matcher: SkillMatcher(),
            generator: generator
        )
        let longText = String(repeating: "x", count: 600)
        let cursorContext = CursorContext(surroundingText: longText, selectedText: nil, appBundleId: "com.apple.dt.Xcode", cursorPosition: nil)
        let enrich = ContextEnrichment(appName: nil, isEditable: nil, focusedRole: nil, vocabularyBias: [:], cursorContext: cursorContext)
        let context = ContextInfo(bundleId: "com.apple.dt.Xcode", appCategory: .development, inputRole: "textField", locale: "zh_CN", enrich: enrich)

        _ = await cleaner.cleanText(transcript: "测试截断", context: context)

        let prompt = try #require(generator.prompts.first)
        let injectedLong = String(repeating: "x", count: 501)
        #expect(prompt.contains(injectedLong) == false)
        let injected500 = String(repeating: "x", count: 500)
        #expect(prompt.contains(injected500))
    }

    @Test
    func llmPrompt_whenNoCursorContext_doesNotInjectCursorInstructions() async throws {
        let generator = TestCapturingPromptGenerator(output: "结果")
        let cleaner = RuleBasedTextCleaner(
            skillStore: TestSkillStore(),
            matcher: SkillMatcher(),
            generator: generator
        )

        _ = await cleaner.cleanText(
            transcript: "普通文本",
            context: .init(bundleId: "com.slack", appCategory: .communication, inputRole: "textField", locale: "zh_CN")
        )

        let prompt = try #require(generator.prompts.first)
        #expect(prompt.contains("光标附近的文本") == false)
        #expect(prompt.contains("选中的文本") == false)
    }
}

struct TestFailingPromptGenerator: PromptGenerating {
    func generateText(from prompt: String) async throws -> String {
        throw PromptGenerationError.unavailable
    }

    func availabilityState() -> FoundationModelAvailabilityState {
        .available
    }
}

final class TestCapturingPromptGenerator: PromptGenerating {
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
