import AppKit
import CoreGraphics
import Foundation
import VoxLiteDomain
import VoxLiteSystem

public final class ClipboardTextInjector: TextInjecting {
    private let logger: LoggerServing
    private let restoreDelayNanos: UInt64
    private let getClipboardString: @Sendable () -> String?
    private let clearClipboard: @Sendable () -> Void
    private let setClipboardString: @Sendable (String) -> Void
    private let pasteCommand: @Sendable () -> Bool
    private let scheduleRestore: (UInt64, () -> Void) -> Void

    public init(
        logger: LoggerServing,
        restoreDelayNanos: UInt64 = 50_000_000,
        getClipboardString: @escaping @Sendable () -> String? = { NSPasteboard.general.string(forType: .string) },
        clearClipboard: @escaping @Sendable () -> Void = { NSPasteboard.general.clearContents() },
        setClipboardString: @escaping @Sendable (String) -> Void = { NSPasteboard.general.setString($0, forType: .string) },
        pasteCommand: @escaping @Sendable () -> Bool = { ClipboardTextInjector.defaultPasteCommand() },
        scheduleRestore: @escaping (UInt64, () -> Void) -> Void = { nanos, action in
            if nanos > 0 {
                usleep(useconds_t(nanos / 1_000))
            }
            action()
        }
    ) {
        self.logger = logger
        self.restoreDelayNanos = restoreDelayNanos
        self.getClipboardString = getClipboardString
        self.clearClipboard = clearClipboard
        self.setClipboardString = setClipboardString
        self.pasteCommand = pasteCommand
        self.scheduleRestore = scheduleRestore
    }

    public func injectText(_ text: String) -> InjectResult {
        let start = Date()
        let backup = getClipboardString()
        clearClipboard()
        setClipboardString(text)

        let pasted = pasteCommand()
        if pasted {
            scheduleRestore(restoreDelayNanos, { [clearClipboard, setClipboardString] in
                guard let backup else { return }
                clearClipboard()
                setClipboardString(backup)
            })
            return InjectResult(success: true, usedClipboardFallback: false, errorCode: nil, latencyMs: elapsed(start))
        }

        logger.warn("inject failed, fallback clipboard available")
        return InjectResult(success: false, usedClipboardFallback: true, errorCode: .injectionFailed, latencyMs: elapsed(start))
    }

    public static func defaultPasteCommand() -> Bool {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func elapsed(_ from: Date) -> Int {
        Int(Date().timeIntervalSince(from) * 1000)
    }
}
