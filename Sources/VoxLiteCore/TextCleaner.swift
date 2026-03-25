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
            let prompt = buildPrompt(profile.template, text: trimmed)
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
            cleanText = normalizeSentence(text)
            routeTag = "沟通风格"
        case .development:
            cleanText = normalizeSentence(text)
            routeTag = "开发风格"
        case .writing:
            cleanText = normalizeSentence(text)
            routeTag = "写作风格"
        case .general:
            cleanText = normalizeSentence(text)
            routeTag = "通用风格"
        }
        return CleanResult(
            cleanText: cleanText,
            confidence: 0.65,
            styleTag: styleTag ?? routeTag,
            usedFallback: true,
            success: true,
            errorCode: nil,
            latencyMs: elapsed(start)
        )
    }

    private func buildPrompt(_ template: String, text: String) -> String {
        let normalized = normalizeSpacing(text)
        if template.contains("{{text}}") {
            return template.replacingOccurrences(of: "{{text}}", with: normalized)
        }
        return "\(template)\n\n\(normalized)"
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

    private func normalizeSpacing(_ text: String) -> String {
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return compact.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureSentenceEndIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("。") || trimmed.hasSuffix(".") || trimmed.hasSuffix("！") || trimmed.hasSuffix("？") {
            return trimmed
        }
        return "\(trimmed)。"
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
