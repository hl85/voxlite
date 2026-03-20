import Foundation
import VoxLiteDomain

public final class RuleBasedTextCleaner: TextCleaning {
    public init() {}

    public func cleanText(transcript: String, context: ContextInfo) -> CleanResult {
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

        switch context.appCategory {
        case .communication:
            return CleanResult(
                cleanText: normalizeSentence(trimmed),
                confidence: 0.92,
                styleTag: "沟通风格",
                success: true,
                errorCode: nil,
                latencyMs: elapsed(start)
            )
        case .development:
            return CleanResult(
                cleanText: convertToDevStyle(trimmed),
                confidence: 0.86,
                styleTag: "开发风格",
                success: true,
                errorCode: nil,
                latencyMs: elapsed(start)
            )
        case .writing:
            return CleanResult(
                cleanText: convertToWritingStyle(trimmed),
                confidence: 0.9,
                styleTag: "写作风格",
                success: true,
                errorCode: nil,
                latencyMs: elapsed(start)
            )
        case .general:
            return CleanResult(
                cleanText: normalizeSentence(trimmed),
                confidence: 0.8,
                styleTag: "通用风格",
                success: true,
                errorCode: nil,
                latencyMs: elapsed(start)
            )
        }
    }

    private func normalizeSentence(_ text: String) -> String {
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return compact.hasSuffix("。") || compact.hasSuffix(".") ? compact : "\(compact)。"
    }

    private func convertToDevStyle(_ text: String) -> String {
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return "feat(voice): \(compact)"
    }

    private func convertToWritingStyle(_ text: String) -> String {
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return "我们建议：\(compact)"
    }

    private func elapsed(_ from: Date) -> Int {
        Int(Date().timeIntervalSince(from) * 1000)
    }
}
