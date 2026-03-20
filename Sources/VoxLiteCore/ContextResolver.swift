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
        return ContextInfo(bundleId: bundleId, appCategory: category, inputRole: "textField", locale: locale)
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
}
