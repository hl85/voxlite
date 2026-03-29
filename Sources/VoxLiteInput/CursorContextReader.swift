import AppKit
import ApplicationServices
import Foundation
import VoxLiteDomain

public final class AXCursorContextReader: CursorContextReading, @unchecked Sendable {

    private let maxContextLength = 500
    private let contextLineRadius = 3

    public init() {}

    public func readContext() async throws -> CursorContext? {
        let systemWide = AXUIElementCreateSystemWide()

        var rawFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &rawFocused) == .success,
              rawFocused != nil else {
            return nil
        }
        let element = rawFocused! as! AXUIElement

        guard let fullText = stringAttribute(element, kAXValueAttribute as CFString),
              !fullText.isEmpty else {
            return nil
        }

        let appBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let selectedText = stringAttribute(element, kAXSelectedTextAttribute as CFString)
        let cursorRange = rangeAttribute(element, kAXSelectedTextRangeAttribute as CFString)
        let surroundingText = contextWindow(fullText: fullText, cursor: cursorRange?.location)

        return CursorContext(
            surroundingText: surroundingText,
            selectedText: selectedText.flatMap { $0.isEmpty ? nil : $0 },
            appBundleId: appBundleId,
            cursorPosition: cursorRange.map { Int($0.location) }
        )
    }

    private func contextWindow(fullText: String, cursor: Int?) -> String {
        let length = fullText.count
        let pos = min(cursor ?? length, length)

        let lines = fullText.components(separatedBy: "\n")
        var charCount = 0
        var cursorLine = 0
        for (i, line) in lines.enumerated() {
            charCount += line.count + 1
            if charCount > pos {
                cursorLine = i
                break
            }
        }

        let start = max(0, cursorLine - contextLineRadius)
        let end = min(lines.count - 1, cursorLine + contextLineRadius)
        let lineWindow = lines[start...end].joined(separator: "\n")

        if lineWindow.count <= maxContextLength {
            return lineWindow
        }

        return characterWindow(fullText: fullText, cursor: pos)
    }

    private func characterWindow(fullText: String, cursor: Int) -> String {
        let length = fullText.count
        let half = maxContextLength / 2
        let startOffset = max(0, cursor - half)
        let endOffset = min(length, cursor + half)
        let s = fullText.index(fullText.startIndex, offsetBy: startOffset)
        let e = fullText.index(fullText.startIndex, offsetBy: endOffset)
        var window = String(fullText[s..<e])
        if window.count > maxContextLength {
            window = String(window[..<window.index(window.startIndex, offsetBy: maxContextLength)])
        }
        return window
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func rangeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axVal = value,
              CFGetTypeID(axVal) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axVal as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
