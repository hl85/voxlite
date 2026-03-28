import Foundation
import AVFAudio
import Speech
import VoxLiteDomain
import VoxLiteSystem

@MainActor
public protocol VoicePipelineStageReporting: AnyObject {
    var stageObserver: VoicePipeline.StageObserver? { get set }
}

public final class UnsupportedPlatformSpeechTranscriber: SpeechTranscribing {
    private let logger: LoggerServing

    public init(logger: LoggerServing) {
        self.logger = logger
    }

    public func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        logger.warn("transcriber unsupported platform file=\(audioFileURL.lastPathComponent)")
        throw SpeechTranscriptionError.transcriberUnavailable
    }
}

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
    func ensureAssets(for locale: Locale, onDeviceOnly: Bool) async throws
    func warmupAnalyzer(for locale: Locale, onDeviceOnly: Bool) async throws
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

    public func ensureAssets(for locale: Locale, onDeviceOnly: Bool) async throws {
        let preset: SpeechTranscriber.Preset = onDeviceOnly ? .transcription : .progressiveTranscription
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installationRequest.downloadAndInstall()
        }
    }

    public func warmupAnalyzer(for locale: Locale, onDeviceOnly: Bool) async throws {
        let preset: SpeechTranscriber.Preset = onDeviceOnly ? .transcription : .progressiveTranscription
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        _ = SpeechAnalyzer(modules: [transcriber])
    }

    public func transcribeFile(url: URL, locale: Locale, onDeviceOnly: Bool) async throws -> String {
        let preset: SpeechTranscriber.Preset = onDeviceOnly ? .transcription : .progressiveTranscription
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        guard SpeechTranscriber.isAvailable else {
            throw SpeechTranscriptionError.transcriberUnavailable
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
public final class OnDeviceSpeechTranscriber: SpeechTranscribing, VoicePipelineStageReporting {
    private let logger: LoggerServing
    private let locale: Locale
    private let authorizationService: SpeechAuthorizationServing
    private let analyzerSession: SpeechAnalyzerSessionServing
    private let warmupService: SpeechTranscriberWarmupService
    private let performanceSampler: PerformanceSampler?
    private let retentionPolicy: ModelRetentionPolicy?

    public var stageObserver: VoicePipeline.StageObserver?

    public init(
        logger: LoggerServing,
        localeIdentifier: String = "zh-CN",
        authorizationService: SpeechAuthorizationServing = SystemSpeechAuthorizationService(),
        analyzerSession: SpeechAnalyzerSessionServing = SystemSpeechAnalyzerSession(),
        warmupService: SpeechTranscriberWarmupService? = nil,
        performanceSampler: PerformanceSampler? = nil,
        retentionPolicy: ModelRetentionPolicy? = nil
    ) {
        self.logger = logger
        self.locale = Locale(identifier: localeIdentifier)
        self.authorizationService = authorizationService
        self.analyzerSession = analyzerSession
        self.warmupService = warmupService ?? SpeechTranscriberWarmupService(
            logger: logger,
            analyzerSession: analyzerSession
        )
        self.performanceSampler = performanceSampler
        self.retentionPolicy = retentionPolicy
    }

    public func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription {
        defer {
            Task {
                await self.evaluateRetentionPolicy()
            }
        }
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
            try await prepareOnDevicePipeline(locale: supportedLocale)
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

    public func resetResources() async {
        logger.info("transcriber manually resetting resources")
        await warmupService.deallocate(locale: locale)
    }

    private func evaluateRetentionPolicy() async {
        guard let sampler = performanceSampler, let policy = retentionPolicy else { return }
        let snapshot = sampler.sample()
        let decision = policy.evaluate(snapshot: snapshot)
        
        if decision.shouldReleaseAnalyzer || decision.shouldReleaseAssets {
            logger.info("transcriber retention policy triggered release decision=\(decision.description)")
            await warmupService.deallocate(locale: locale)
        }
    }

    private func elapsed(_ from: Date) -> Int {
        Int(Date().timeIntervalSince(from) * 1000)
    }

    private func prepareOnDevicePipeline(locale: Locale) async throws {
        stageObserver?(.init(stage: .assetCheck, phase: .started))
        stageObserver?(.init(stage: .assetInstall, phase: .started))
        stageObserver?(.init(stage: .analyzerCreate, phase: .started))
        stageObserver?(.init(stage: .analyzerWarmup, phase: .started))
        let preparationStart = Date()
        do {
            let disposition = try await warmupService.prepareForRecognition(locale: locale)
            let latency = elapsed(preparationStart)
            logger.info("transcriber warmup disposition=\(String(describing: disposition)) locale=\(locale.identifier)")
            stageObserver?(.init(stage: .assetCheck, phase: .completed, success: true, errorCode: nil, latencyMs: latency))
            stageObserver?(.init(stage: .assetInstall, phase: .completed, success: true, errorCode: nil, latencyMs: latency))
            stageObserver?(.init(stage: .analyzerCreate, phase: .completed, success: true, errorCode: nil, latencyMs: latency))
            stageObserver?(.init(stage: .analyzerWarmup, phase: .completed, success: true, errorCode: nil, latencyMs: latency))
        } catch {
            let latency = elapsed(preparationStart)
            stageObserver?(.init(stage: .assetCheck, phase: .completed, success: false, errorCode: .transcriptionUnavailable, latencyMs: latency))
            stageObserver?(.init(stage: .assetInstall, phase: .completed, success: false, errorCode: .transcriptionUnavailable, latencyMs: latency))
            stageObserver?(.init(stage: .analyzerCreate, phase: .completed, success: false, errorCode: .transcriptionUnavailable, latencyMs: latency))
            stageObserver?(.init(stage: .analyzerWarmup, phase: .completed, success: false, errorCode: .transcriptionUnavailable, latencyMs: latency))
            throw error
        }
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
