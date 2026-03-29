import AVFoundation
import ApplicationServices
import Foundation
import AppKit
import Speech
import os
import VoxLiteDomain

public final class ConsoleLogger: LoggerServing, Sendable {
    private let logger = Logger(subsystem: "ai.holoo.voxlite", category: "App")

    public init() {}

    public func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    public func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    public func warn(_ message: String) { logger.warning("\(message, privacy: .public)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}

public final class InMemoryMetrics: MetricsServing, @unchecked Sendable {
    public struct MetricEvent: Sendable {
        public let name: String
        public let success: Bool
        public let errorCode: VoxErrorCode?
        public let latencyMs: Int
    }

    private let lock = NSLock()
    public private(set) var events: [MetricEvent] = []

    public init() {}

    public func record(event: String, success: Bool, errorCode: VoxErrorCode?, latencyMs: Int) {
        lock.lock()
        events.append(MetricEvent(name: event, success: success, errorCode: errorCode, latencyMs: latencyMs))
        lock.unlock()
    }

    public func percentile(_ event: String, _ value: Double) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let values = events
            .filter { $0.name == event && $0.success }
            .map(\.latencyMs)
            .sorted()
        guard !values.isEmpty else { return nil }
        let index = max(0, min(values.count - 1, Int(Double(values.count - 1) * value)))
        return values[index]
    }
}

public final class PermissionManager: PermissionManaging, @unchecked Sendable {
    public init() {}

    public func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func hasRequiredPermissions() -> Bool {
        currentPermissionSnapshot().allGranted
    }

    public func currentPermissionSnapshot() -> PermissionSnapshot {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        let accessibility = checkAccessibilityPermission()
        return PermissionSnapshot(
            microphoneGranted: mic,
            speechRecognitionGranted: speech,
            accessibilityGranted: accessibility
        )
    }

    public func requestPermission(_ item: PermissionItem) async -> Bool {
        switch item {
        case .microphone:
            if #available(macOS 14.0, *) {
                return await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                return await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .audio) { status in
                        continuation.resume(returning: status)
                    }
                }
            }
        case .speechRecognition:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .accessibility:
            requestAccessibilityPermission()
            return checkAccessibilityPermission()
        }
    }

    public func openSystemSettings(for item: PermissionItem) {
        let urlString: String
        switch item {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
