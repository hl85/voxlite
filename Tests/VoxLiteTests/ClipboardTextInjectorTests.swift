import Testing
@testable import VoxLiteDomain
@testable import VoxLiteOutput

struct ClipboardTextInjectorTests {
    final class ClipboardBox: @unchecked Sendable {
        var value: String

        init(_ value: String) {
            self.value = value
        }
    }

    @Test
    func injectText_whenPasteSucceeds_restoresClipboardBackup() {
        let clipboard = ClipboardBox("旧内容")
        let injector = ClipboardTextInjector(
            logger: TestLogger(),
            restoreDelayNanos: 0,
            getClipboardString: { clipboard.value },
            clearClipboard: { clipboard.value = "" },
            setClipboardString: { clipboard.value = $0 },
            pasteCommand: { true },
            scheduleRestore: { _, action in action() }
        )

        let result = injector.injectText("新内容")

        #expect(result.success)
        #expect(result.usedClipboardFallback == false)
        #expect(clipboard.value == "旧内容")
    }

    @Test
    func injectText_whenPasteFails_keepsFallbackClipboard() {
        let clipboard = ClipboardBox("旧内容")
        let injector = ClipboardTextInjector(
            logger: TestLogger(),
            restoreDelayNanos: 0,
            getClipboardString: { clipboard.value },
            clearClipboard: { clipboard.value = "" },
            setClipboardString: { clipboard.value = $0 },
            pasteCommand: { false },
            scheduleRestore: { _, action in action() }
        )

        let result = injector.injectText("新内容")

        #expect(result.success == false)
        #expect(result.usedClipboardFallback)
        #expect(result.errorCode == .injectionFailed)
        #expect(clipboard.value == "新内容")
    }
}
