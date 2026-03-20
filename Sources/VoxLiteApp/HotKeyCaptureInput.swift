import AppKit
import Carbon
import SwiftUI
import VoxLiteDomain

// MARK: - HotKey Capture Input (NSViewRepresentable)

struct HotKeyCaptureInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var isCapturing: Bool
    let onStartCapture: () -> Void
    let onCapture: (HotKeyConfiguration?) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> HotKeyCaptureTextField {
        let field = HotKeyCaptureTextField()
        field.delegate = context.coordinator
        field.isEditable = false
        field.isBezeled = true
        field.isBordered = true
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.alignment = .left
        field.backgroundColor = NSColor(Color(hex: "#17223f"))
        field.textColor = NSColor(Color(hex: "#c7d4ff"))
        field.onMouseDown = { onStartCapture() }
        field.onCapture = { config in onCapture(config) }
        field.onCancel = { onCancel() }
        field.onSubmit = { onSubmit() }
        return field
    }

    func updateNSView(_ nsView: HotKeyCaptureTextField, context: Context) {
        nsView.stringValue = text.isEmpty ? "点击并按下快捷键" : text
        nsView.isCapturing = isCapturing
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, NSTextFieldDelegate {}
}

// MARK: - HotKey Capture TextField

final class HotKeyCaptureTextField: NSTextField {
    var onMouseDown: (() -> Void)?
    var onCapture: ((HotKeyConfiguration?) -> Void)?
    var onCancel: (() -> Void)?
    var onSubmit: (() -> Void)?
    var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onMouseDown?()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { onCancel?(); return }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            onSubmit?(); return
        }
        let keyCode = event.keyCode
        if isModifierOnlyKey(keyCode) { return }
        let modifiers = buildModifierMask(from: event.modifierFlags)
        onCapture?(HotKeyConfiguration(keyCode: keyCode, modifiers: modifiers))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else { super.flagsChanged(with: event); return }
        if event.modifierFlags.contains(.function) {
            onCapture?(HotKeyConfiguration.defaultConfiguration)
        }
    }

    private func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
         kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl, kVK_Function]
            .contains(Int(keyCode))
    }

    private func buildModifierMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= HotKeyConfiguration.controlModifierMask }
        if flags.contains(.option)  { mask |= HotKeyConfiguration.optionModifierMask }
        if flags.contains(.shift)   { mask |= HotKeyConfiguration.shiftModifierMask }
        if flags.contains(.command) { mask |= HotKeyConfiguration.commandModifierMask }
        return mask
    }
}
