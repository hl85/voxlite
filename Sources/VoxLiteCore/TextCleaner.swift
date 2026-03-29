import Foundation
import VoxLiteDomain
import VoxLiteSystem
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
public protocol PromptGenerating {
    func generateText(from prompt: String) async throws -> String
    func availabilityState() -> FoundationModelAvailabilityState
}

public enum PromptGenerationError: Error {
    case unavailable
    case emptyResult
}

public enum FoundationModelAvailabilityState: Equatable, Sendable {
    case available
    case modelNotReady
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case unavailable
}

@MainActor
public protocol FoundationModelAvailabilityProviding {
    func foundationModelAvailability() -> FoundationModelAvailabilityState
}

public final class FoundationModelPromptGenerator: PromptGenerating {
    public init() {}

    public func generateText(from prompt: String) async throws -> String {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw PromptGenerationError.unavailable
            }
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw PromptGenerationError.emptyResult
            }
            return content
        }
#endif
        throw PromptGenerationError.unavailable
    }

    public func availabilityState() -> FoundationModelAvailabilityState {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .modelNotReady:
                    return .modelNotReady
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceNotEnabled
                case .deviceNotEligible:
                    return .deviceNotEligible
                @unknown default:
                    return .unavailable
                }
            }
        }
#endif
        return .deviceNotEligible
    }
}

public final class RuleBasedTextCleaner: TextCleaning, FoundationModelAvailabilityProviding {
    private let skillStore: SkillStore
    private let matcher: SkillMatcher
    private let generator: PromptGenerating

    public init(
        skillStore: SkillStore = FileSkillStore(),
        matcher: SkillMatcher = SkillMatcher(),
        generator: PromptGenerating = FoundationModelPromptGenerator()
    ) {
        self.skillStore = skillStore
        self.matcher = matcher
        self.generator = generator
    }

    public func cleanText(transcript: String, context: ContextInfo) async -> CleanResult {
        let start = Date()
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CleanResult(
                cleanText: "",
                confidence: 0,
                styleTag: "empty",
                success: false,
                errorCode: .cleaningUnavailable,
                latencyMs: elapsed(start)
            )
        }

        let snapshot = skillStore.loadSkills()
        let skillId = matcher.resolveSkillId(
            bundleId: context.bundleId,
            category: context.appCategory,
            matching: snapshot.matching
        )
        if let profile = snapshot.profiles.first(where: { $0.id == skillId }) {
            let prompt = buildPrompt(profile.template, text: trimmed, context: context)
            if let generated = await generateText(prompt: prompt) {
                return CleanResult(
                    cleanText: generated,
                    confidence: 0.92,
                    styleTag: profile.name,
                    success: true,
                    errorCode: nil,
                    latencyMs: elapsed(start)
                )
            }
            return fallbackClean(trimmed, context: context, start: start, styleTag: "\(profile.name)-降级")
        }
        return fallbackClean(trimmed, context: context, start: start)
    }

    public func foundationModelAvailability() -> FoundationModelAvailabilityState {
        generator.availabilityState()
    }

    private func fallbackClean(_ text: String, context: ContextInfo, start: Date, styleTag: String? = nil) -> CleanResult {
        let cleanText: String
        let routeTag: String
        switch context.appCategory {
        case .communication:
            cleanText = cleanCommunicationText(text)
            routeTag = "沟通风格"
        case .development:
            cleanText = cleanDevelopmentText(text)
            routeTag = "开发风格"
        case .writing:
            cleanText = cleanWritingText(text)
            routeTag = "写作风格"
        case .general:
            cleanText = normalizeSentence(text)
            routeTag = "通用风格"
        }
        let contextualizedText = finalizeCleanText(cleanText, context: context)
        return CleanResult(
            cleanText: contextualizedText,
            confidence: 0.65,
            styleTag: styleTag ?? routeTag,
            usedFallback: true,
            success: true,
            errorCode: nil,
            latencyMs: elapsed(start)
        )
    }

    private func buildPrompt(_ template: String, text: String, context: ContextInfo) -> String {
        let normalized = normalizePromptInput(text, for: context.appCategory, context: context)
        let routeInstructions = promptInstructions(for: context.appCategory)
        let enrichInstructions = promptContextInstructions(context)
        let promptBody: String
        if template.contains("{{text}}") {
            promptBody = template.replacingOccurrences(of: "{{text}}", with: normalized)
        } else {
            promptBody = "\(template)\n\n\(normalized)"
        }
        let instructions = [routeInstructions, enrichInstructions].filter { $0.isEmpty == false }
        guard instructions.isEmpty == false else {
            return promptBody
        }
        return "\(instructions.joined(separator: "\n"))\n\n\(promptBody)"
    }

    private func generateText(prompt: String) async -> String? {
        do {
            let generated = try await generator.generateText(from: prompt)
            let normalized = normalizeSpacing(generated)
            return normalized.isEmpty ? nil : ensureSentenceEndIfNeeded(normalized)
        } catch {
            return nil
        }
    }

    private func normalizeSentence(_ text: String) -> String {
        let compact = normalizeSpacing(text)
        return compact.hasSuffix("。") || compact.hasSuffix(".") ? compact : "\(compact)。"
    }

    private func cleanCommunicationText(_ text: String) -> String {
        let stripped = stripFillerWords(text)
        let clauses = splitCommunicationClauses(stripped)
        let normalizedClauses = clauses.map { clause in
            normalizeCommunicationClause(clause)
        }.filter { $0.isEmpty == false }
        let joined = normalizedClauses.joined(separator: "，")
        return ensureChineseSentenceTermination(joined)
    }

    private func cleanDevelopmentText(_ text: String) -> String {
        let stripped = stripFillerWords(text)
        let normalized = normalizeDevelopmentClause(stripped)
        return ensureChineseSentenceTermination(normalized)
    }

    private func cleanWritingText(_ text: String) -> String {
        let stripped = normalizeWritingVocabulary(stripFillerWords(text))
        let clauses = splitWritingClauses(stripped)
        let normalizedClauses = clauses.map { clause in
            normalizeWritingClause(clause)
        }.filter { $0.isEmpty == false }

        guard normalizedClauses.isEmpty == false else {
            return ""
        }

        if normalizedClauses.count == 1 {
            return ensureChineseSentenceTermination(normalizedClauses[0])
        }

        let paragraphs = normalizedClauses.enumerated().map { index, clause in
            if index == 0 {
                return ensureChineseSentenceTermination(clause)
            }
            return ensureChineseSentenceTermination("此外，\(lowercaseFirstCharacterIfNeeded(clause))")
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private func normalizeSpacing(_ text: String) -> String {
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return compact.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizePromptInput(_ text: String, for category: AppCategory, context: ContextInfo) -> String {
        let normalized: String
        switch category {
        case .communication:
            normalized = cleanCommunicationText(text)
        case .development:
            normalized = cleanDevelopmentText(text)
        case .writing:
            normalized = cleanWritingText(text)
        case .general:
            normalized = normalizeSentence(text)
        }
        return finalizeCleanText(normalized, context: context)
    }

    private func promptInstructions(for category: AppCategory) -> String {
        switch category {
        case .communication:
            return "沟通路由补充要求：优化口语短句断句；删除“嗯”“啊”“那个”等口头禅；补全自然的逗号和句号；保持表达自然、直接、适合即时沟通。"
        case .development:
            return "开发路由补充要求：保留 camelCase、snake_case、API 名称、路径、命令和技术术语原样；保留“添加”“修改”“删除”等命令式语气；不要将技术表达过度书面化。"
        case .writing:
            return "写作路由补充要求：将口语整理为结构清晰的正式书面表达；必要时改写为分段结构；确保句意完整、标点齐全、语气正式。"
        case .general:
            return ""
        }
    }

    private func promptContextInstructions(_ context: ContextInfo) -> String {
        var instructions: [String] = []
        if let appName = context.enrich?.appName, appName.isEmpty == false {
            instructions.append("当前应用：\(appName)。")
        }
        let focusedRole = context.enrich?.focusedRole ?? context.inputRole
        if focusedRole.isEmpty == false {
            instructions.append("焦点角色：\(focusedRole)。")
        }
        if let isEditable = context.enrich?.isEditable {
            instructions.append(isEditable ? "当前焦点可编辑，可直接输出可粘贴正文。" : "当前焦点可能不可编辑，请保持轻量整理，不要臆造额外内容。")
        }
        let bias = context.enrich?.vocabularyBias ?? [:]
        if bias.isEmpty == false {
            let serialized = bias.keys.sorted().map { "\($0)→\(bias[$0] ?? "")" }.joined(separator: "，")
            instructions.append("词汇偏置：优先使用以下写法：\(serialized)。")
        }
        if let cursor = context.enrich?.cursorContext {
            let truncated = String(cursor.surroundingText.prefix(500))
            instructions.append("用户当前输入上下文（光标附近的文本）：\n「\(truncated)」\n请参考此上下文来提高对专有名词、缩写和上下文相关术语的识别准确性。")
            if let selected = cursor.selectedText, selected.isEmpty == false {
                instructions.append("用户当前选中的文本：「\(selected)」")
            }
        }
        return instructions.joined(separator: "\n")
    }

    private func splitCommunicationClauses(_ text: String) -> [String] {
        let normalized = normalizeSpacing(
            text
                .replacingOccurrences(of: #"(?:[，,。.!！？；;、]+|\s{2,})"#, with: "|", options: .regularExpression)
                .replacingOccurrences(of: " 然后 ", with: "|", options: .literal)
                .replacingOccurrences(of: " 接着 ", with: "|", options: .literal)
                .replacingOccurrences(of: " 另外 ", with: "|", options: .literal)
        )
        return splitByPipe(normalized)
    }

    private func splitWritingClauses(_ text: String) -> [String] {
        let normalized = normalizeSpacing(
            text
                .replacingOccurrences(of: #"(?:[。！？；;]+|\n+)"#, with: "|", options: .regularExpression)
                .replacingOccurrences(of: "，", with: "|")
                .replacingOccurrences(of: ",", with: "|")
        )
        return splitByPipe(normalized)
    }

    private func splitByPipe(_ text: String) -> [String] {
        text
            .split(separator: "|")
            .map { normalizeSpacing(String($0)) }
            .filter { $0.isEmpty == false }
    }

    private func stripFillerWords(_ text: String) -> String {
        var result = text
        let patterns = [#"(^|[\s，,。.!！？；;])(?:嗯+|啊+|呃+|唉|那个|就是|这个)(?=$|[\s，,。.!！？；;])"#]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }
        return normalizeSpacing(result)
    }

    private func normalizeCommunicationClause(_ clause: String) -> String {
        let trimmed = normalizeSpacing(clause)
        guard trimmed.isEmpty == false else { return "" }
        return trimmed
    }

    private func normalizeDevelopmentClause(_ clause: String) -> String {
        var trimmed = normalizeSpacing(clause)
        guard trimmed.isEmpty == false else { return "" }

        let commandStarters = ["添加", "修改", "删除", "更新", "修复", "保留", "移除", "重命名", "优化", "补充", "合并", "拆分", "检查"]
        if commandStarters.contains(where: { trimmed.hasPrefix($0) }) == false,
           let first = trimmed.first,
           isLowercaseEnglish(first) {
            trimmed = String(first).uppercased() + trimmed.dropFirst()
        }
        return trimmed
    }

    private func normalizeWritingClause(_ clause: String) -> String {
        let trimmed = normalizeSpacing(clause)
        guard trimmed.isEmpty == false else { return "" }
        return trimmed
    }

    private func normalizeWritingVocabulary(_ text: String) -> String {
        var result = normalizeSpacing(text)
        let replacements: [(String, String)] = [
            ("我想说", "我认为"),
            ("我觉得", "我认为"),
            ("想一下", "进一步分析"),
            ("弄一下", "处理"),
            ("搞一下", "完成"),
            ("有点", "较为"),
            ("先这样", "暂定如此")
        ]
        for (source, target) in replacements {
            result = result.replacingOccurrences(of: source, with: target)
        }
        return result
    }

    private func ensureChineseSentenceTermination(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        if trimmed.hasSuffix("。") || trimmed.hasSuffix("！") || trimmed.hasSuffix("？") {
            return trimmed
        }
        return "\(trimmed)。"
    }

    private func lowercaseFirstCharacterIfNeeded(_ text: String) -> String {
        guard let first = text.first else { return text }
        guard isUppercaseEnglish(first) else { return text }
        return String(first).lowercased() + text.dropFirst()
    }

    private func isLowercaseEnglish(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.lowercaseLetters.contains($0) }
    }

    private func isUppercaseEnglish(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
    }

    private func ensureSentenceEndIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("。") || trimmed.hasSuffix(".") || trimmed.hasSuffix("！") || trimmed.hasSuffix("？") {
            return trimmed
        }
        return "\(trimmed)。"
    }

    private func finalizeCleanText(_ text: String, context: ContextInfo) -> String {
        let editable = context.enrich?.isEditable
        let biased = applyVocabularyBias(to: text, bias: context.enrich?.vocabularyBias ?? [:])
        guard editable == false else {
            return biased
        }
        return normalizeSpacing(
            biased
                .replacingOccurrences(of: "\n\n", with: " ")
                .replacingOccurrences(of: "。", with: "")
        )
    }

    private func applyVocabularyBias(to text: String, bias: [String: String]) -> String {
        guard bias.isEmpty == false else {
            return text
        }
        var result = text
        for source in bias.keys.sorted(by: { $0.count > $1.count }) {
            guard let target = bias[source], source.isEmpty == false, target.isEmpty == false else {
                continue
            }
            if source.range(of: "^[A-Za-z0-9_\\-]+$", options: .regularExpression) != nil {
                let escaped = NSRegularExpression.escapedPattern(for: source)
                result = result.replacingOccurrences(
                    of: "\\b\(escaped)\\b",
                    with: target,
                    options: [.regularExpression, .caseInsensitive]
                )
            } else {
                result = result.replacingOccurrences(of: source, with: target)
            }
        }
        return result
    }

    private func elapsed(_ from: Date) -> Int {
        Int(Date().timeIntervalSince(from) * 1000)
    }
}

@MainActor
public final class FoundationModelAvailabilityProbe: FoundationModelAvailabilityProviding {
    private let generator: PromptGenerating

    public init(generator: PromptGenerating = FoundationModelPromptGenerator()) {
        self.generator = generator
    }

    public func foundationModelAvailability() -> FoundationModelAvailabilityState {
        generator.availabilityState()
    }
}
