import Foundation
import AVFAudio
import Speech
import VoxLiteDomain
import VoxLiteSystem

@available(macOS 26.0, iOS 26.0, *)
public enum SpeechAuthorizationState: Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

@available(macOS 26.0, iOS 26.0, *)
public protocol SpeechAuthorizationServing: Sendable {
    func authorizationStatus() async -> SpeechAuthorizationState
    func requestAuthorization() async -> SpeechAuthorizationState
}

@available(macOS 26.0, iOS 26.0, *)
public protocol SpeechAnalyzerSessionServing: Sendable {
    func supportedLocale(equivalentTo locale: Locale) async -> Locale?
    func transcribeFile(url: URL, locale: Locale, onDeviceOnly: Bool) async throws -> String
}

@available(macOS 26.0, iOS 26.0, *)
public struct SystemSpeechAuthorizationService: SpeechAuthorizationServing {
    public init() {}

    public func authorizationStatus() async -> SpeechAuthorizationState {
        .authorized
    }

    public func requestAuthorization() async -> SpeechAuthorizationState {
        .authorized
    }
}

@available(macOS 26.0, iOS 26.0, *)
public struct SystemSpeechAnalyzerSession: SpeechAnalyzerSessionServing {
    public init() {}

    public func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    public func transcribeFile(url: URL, locale: Locale, onDeviceOnly: Bool) async throws -> String {
        let preset: SpeechTranscriber.Preset = onDeviceOnly ? .transcription : .progressiveTranscription
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        guard SpeechTranscriber.isAvailable else {
            throw SpeechTranscriptionError.transcriberUnavailable
        }
        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installationRequest.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: url)
        async let text = transcriber.results.reduce(into: "") { partial, result in
            partial += String(result.text.characters)
        }
        if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await text
    }
}

@available(macOS 26.0, iOS 26.0, *)
public final class OnDeviceSpeechTranscriber: SpeechTranscribing {
    private let logger: LoggerServing
    private let locale: Locale
    private let authorizationService: SpeechAuthorizationServing
    private let analyzerSession: SpeechAnalyzerSessionServing

    public init(
        logger: LoggerServing,
        localeIdentifier: String = "zh-CN",
        authorizationService: SpeechAuthorizationServing = SystemSpeechAuthorizationService(),
        analyzerSession: SpeechAnalyzerSessionServing = SystemSpeechAnalyzerSession()
    ) {
        self.logger = logger
        locale = Locale(identifier: localeIdentifier)
        self.authorizationService = authorizationService
        self.analyzerSession = analyzerSession
    }

    public func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        let start = Date()
        logger.info("transcriber begin audioFile=\(audioFileURL.lastPathComponent)")
        guard FileManager.default.fileExists(atPath: audioFileURL.path(percentEncoded: false)) else {
            logger.warn("transcriber empty audio payload")
            throw SpeechTranscriptionError.noResult
        }
        var authorization = await authorizationService.authorizationStatus()
        if authorization == .notDetermined {
            authorization = await authorizationService.requestAuthorization()
        }
        guard authorization == .authorized else {
            logger.warn("transcriber permission denied status=\(authorization)")
            throw SpeechTranscriptionError.permissionDenied
        }
        guard let supportedLocale = await analyzerSession.supportedLocale(equivalentTo: locale) else {
            logger.warn("transcriber recognizer unavailable locale=\(locale.identifier)")
            throw SpeechTranscriptionError.localeNotSupported(locale.identifier)
        }
        let elapsedHint = elapsedMs ?? 0
        logger.info("transcriber on-device path file=\(audioFileURL.lastPathComponent) elapsedHint=\(elapsedHint)ms")
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)[.size] as? NSNumber)?.intValue ?? -1
        logger.info("transcriber audio file size=\(fileSize) bytes")
        do {
            let transcript = try await recognizeFromFile(
                url: audioFileURL,
                locale: supportedLocale,
                elapsedMs: elapsedHint,
                onDeviceOnly: true,
                pathTag: "on-device"
            )
            if !transcript.isEmpty {
                logger.info("transcriber on-device success textLen=\(transcript.count)")
                return SpeechTranscription(text: transcript, latencyMs: elapsed(start), usedOnDevice: true)
            }
            logger.warn("transcriber on-device empty result")
        } catch {
            logger.warn("transcriber on-device error=\(error.localizedDescription)")
        }
        do {
            let transcript = try await recognizeFromFile(
                url: audioFileURL,
                locale: supportedLocale,
                elapsedMs: elapsedHint,
                onDeviceOnly: false,
                pathTag: "network-fallback"
            )
            if !transcript.isEmpty {
                logger.info("transcriber network fallback success textLen=\(transcript.count)")
                return SpeechTranscription(text: transcript, latencyMs: elapsed(start), usedOnDevice: false)
            }
        } catch {
            logger.warn("transcriber network-fallback error=\(error.localizedDescription)")
        }
        logger.error("transcriber all recognition paths failed")
        throw SpeechTranscriptionError.noResult
    }

    private func elapsed(_ from: Date) -> Int {
        Int(Date().timeIntervalSince(from) * 1000)
    }

    private func recognizeFromFile(
        url: URL,
        locale: Locale,
        elapsedMs: Int,
        onDeviceOnly: Bool,
        pathTag: String
    ) async throws -> String {
        let timeout = recognitionTimeoutSeconds(elapsedMs: elapsedMs, onDeviceOnly: onDeviceOnly)
        let analyzerSession = self.analyzerSession
        do {
            let raw = try await withTimeout(seconds: timeout) {
                try await analyzerSession.transcribeFile(url: url, locale: locale, onDeviceOnly: onDeviceOnly)
            }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is TimeoutError {
            logger.warn("transcriber \(pathTag) timed out timeout=\(timeout)")
            throw SpeechTranscriptionError.timedOut
        } catch let error as SpeechTranscriptionError {
            throw error
        } catch {
            throw SpeechTranscriptionError.underlying(error.localizedDescription)
        }
    }

    private func recognitionTimeoutSeconds(elapsedMs: Int, onDeviceOnly: Bool) -> Double {
        let base = max(3.0, min(12.0, Double(elapsedMs) / 1000.0 * 0.45))
        return onDeviceOnly ? base : max(base, 6.0)
    }
}

@available(macOS 26.0, iOS 26.0, *)
private struct TimeoutError: Error {}

@available(macOS 26.0, iOS 26.0, *)
private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}
