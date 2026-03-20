import AppKit
import Carbon
import CoreGraphics
import Foundation
import VoxLiteDomain

public final class HotKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onPress: @Sendable () -> Void
    private let onRelease: @Sendable () -> Void
    private var isPressed = false
    private var configuration: HotKeyConfiguration

    public var isRecording = false

    public init(configuration: HotKeyConfiguration = .defaultConfiguration, onPress: @escaping @Sendable () -> Void, onRelease: @escaping @Sendable () -> Void) {
        self.configuration = configuration
        self.onPress = onPress
        self.onRelease = onRelease
    }

    public func updateConfiguration(_ newConfig: HotKeyConfiguration) {
        let wasRunning = eventTap != nil
        if wasRunning {
            stop()
        }
        configuration = newConfig
        if wasRunning {
            start()
        }
    }

    public func simulateFnKeyPress() {
        if !isPressed {
            isPressed = true
            onPress()
        }
    }

    public func simulateFnKeyRelease() {
        if isPressed {
            isPressed = false
            onRelease()
        }
    }

    public func start() {
        guard eventTap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            guard type == .flagsChanged || type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
            monitor.handleEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var eventsOfInterest: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.tapDisabledByTimeout.rawValue) | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        if configuration.keyCode != HotKeyConfiguration.fnKeyCode {
            eventsOfInterest |= (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventsOfInterest,
                callback: callback,
                userInfo: userInfo
            )
        else {
            print("Failed to create CGEventTap. Ensure Accessibility permissions are granted.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isPressed = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if configuration.keyCode == HotKeyConfiguration.fnKeyCode {
            handleFnMode(type: type, event: event)
        } else {
            handleCustomKeyMode(type: type, event: event)
        }
    }

    private func handleFnMode(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }
        let flags = event.flags
        let functionPressed = flags.contains(.maskSecondaryFn)
        if functionPressed && !isPressed {
            isPressed = true
            onPress()
            return
        }
        if !functionPressed && isPressed {
            isPressed = false
            onRelease()
        }
    }

    private func handleCustomKeyMode(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let currentModifiers = buildModifierFlags(flags)
            if keyCode == UInt32(configuration.keyCode) && currentModifiers == configuration.modifiers {
                if !isPressed {
                    isPressed = true
                    onPress()
                }
            }
        case .keyUp:
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let currentModifiers = buildModifierFlags(flags)
            if keyCode == UInt32(configuration.keyCode) && currentModifiers == configuration.modifiers {
                if isPressed {
                    isPressed = false
                    onRelease()
                }
            }
        default:
            break
        }
    }

    private func buildModifierFlags(_ flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskControl) {
            modifiers |= HotKeyConfiguration.controlModifierMask
        }
        if flags.contains(.maskAlternate) {
            modifiers |= HotKeyConfiguration.optionModifierMask
        }
        if flags.contains(.maskShift) {
            modifiers |= HotKeyConfiguration.shiftModifierMask
        }
        if flags.contains(.maskCommand) {
            modifiers |= HotKeyConfiguration.commandModifierMask
        }
        return modifiers
    }
}
