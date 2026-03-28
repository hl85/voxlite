import AppKit
import Foundation
import VoxLiteDomain

public final class FrontmostContextResolver: ContextResolving {
    public init() {}

    public func resolveContext() -> ContextInfo {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleId = app?.bundleIdentifier ?? "unknown"
        let locale = Locale.current.identifier
        let category = categoryForBundle(bundleId)
        let enrich = buildEnrichment(for: app, bundleId: bundleId, category: category)
        let inputRole = enrich?.focusedRole ?? "textField"
        return ContextInfo(bundleId: bundleId, appCategory: category, inputRole: inputRole, locale: locale, enrich: enrich)
    }

    func buildEnrichment(for app: NSRunningApplication?, bundleId: String, category: AppCategory) -> ContextEnrichment? {
        let appName = app?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusedRole = inferFocusedRole(bundleId: bundleId, category: category)
        let isEditable = inferEditable(bundleId: bundleId, category: category)
        let vocabularyBias = vocabularyBias(bundleId: bundleId, category: category)
        let enrichment = ContextEnrichment(
            appName: appName?.isEmpty == true ? nil : appName,
            isEditable: isEditable,
            focusedRole: focusedRole,
            vocabularyBias: vocabularyBias
        )
        return enrichment.isEmpty ? nil : enrichment
    }

    private func categoryForBundle(_ bundleId: String) -> AppCategory {
        let lowered = bundleId.lowercased()
        if lowered.contains("slack") || lowered.contains("wecom") || lowered.contains("feishu") || lowered.contains("wechat") {
            return .communication
        }
        if lowered.contains("xcode") || lowered.contains("terminal") || lowered.contains("vscode") {
            return .development
        }
        if lowered.contains("notion") || lowered.contains("pages") {
            return .writing
        }
        return .general
    }

    private func inferFocusedRole(bundleId: String, category: AppCategory) -> String? {
        let lowered = bundleId.lowercased()
        if lowered.contains("xcode") {
            return "sourceEditor"
        }
        if lowered.contains("terminal") {
            return "terminal"
        }
        if lowered.contains("slack") || lowered.contains("wecom") || lowered.contains("feishu") || lowered.contains("wechat") {
            return "chatInput"
        }
        switch category {
        case .writing:
            return "documentEditor"
        case .communication:
            return "messageField"
        default:
            return nil
        }
    }

    private func inferEditable(bundleId: String, category: AppCategory) -> Bool? {
        let lowered = bundleId.lowercased()
        if lowered == "unknown" {
            return nil
        }
        if lowered.contains("finder") {
            return false
        }
        switch category {
        case .communication, .development, .writing:
            return true
        case .general:
            return nil
        }
    }

    private func vocabularyBias(bundleId: String, category: AppCategory) -> [String: String] {
        let lowered = bundleId.lowercased()
        if lowered.contains("xcode") || lowered.contains("vscode") {
            return [
                "cmd": "command",
                "api": "API",
                "sdk": "SDK",
                "ios": "iOS",
                "macos": "macOS"
            ]
        }
        if lowered.contains("terminal") {
            return [
                "gitlab": "GitLab",
                "github": "GitHub",
                "cli": "CLI"
            ]
        }
        switch category {
        case .communication:
            return ["稍后": "晚点", "收到": "收到"]
        case .writing:
            return ["想法": "观点", "说明": "阐述"]
        default:
            return [:]
        }
    }
}
