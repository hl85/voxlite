import Foundation
import Testing
@testable import VoxLiteCore
@testable import VoxLiteDomain
@testable import VoxLiteSystem

struct SpeechTranscriberWarmupTests {

    final class MockLogger: @unchecked Sendable, LoggerServing {
        var infoMessages: [String] = []
        var warnMessages: [String] = []
        var errorMessages: [String] = []

        func debug(_ message: String) {}
        func info(_ message: String) { infoMessages.append(message) }
        func warn(_ message: String) { warnMessages.append(message) }
        func error(_ message: String) { errorMessages.append(message) }
    }

    actor MockSpeechAnalyzerSession: SpeechAnalyzerSessionServing {
        enum MockError: Error {
            case ensureFailed
            case warmupFailed
            case transcribeFailed
        }

        private(set) var ensureCalls: [String] = []
        private(set) var warmupCalls: [String] = []
        private(set) var transcribeCalls: [(locale: String, onDeviceOnly: Bool)] = []
        var supportedLocaleToReturn: Locale?
        var ensureDelayNanos: UInt64 = 0
        var warmupDelayNanos: UInt64 = 0
        var onDeviceTranscription: Result<String, Error> = .success("设备端结果")
        var fallbackTranscription: Result<String, Error> = .success("回退结果")
        var failEnsureLocales: Set<String> = []
        var failWarmupLocales: Set<String> = []

        init(supportedLocale: Locale? = Locale(identifier: "zh-CN")) {
            self.supportedLocaleToReturn = supportedLocale
        }

        func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
            supportedLocaleToReturn
        }

        func ensureAssets(for locale: Locale, onDeviceOnly: Bool) async throws {
            ensureCalls.append(locale.identifier)
            if ensureDelayNanos > 0 {
                try await Task.sleep(nanoseconds: ensureDelayNanos)
            }
            if failEnsureLocales.contains(locale.identifier) {
                throw MockError.ensureFailed
            }
        }

        func warmupAnalyzer(for locale: Locale, onDeviceOnly: Bool) async throws {
            warmupCalls.append(locale.identifier)
            if warmupDelayNanos > 0 {
                try await Task.sleep(nanoseconds: warmupDelayNanos)
            }
            if failWarmupLocales.contains(locale.identifier) {
                throw MockError.warmupFailed
            }
        }

        func transcribeFile(url: URL, locale: Locale, onDeviceOnly: Bool) async throws -> String {
            transcribeCalls.append((locale.identifier, onDeviceOnly))
            if onDeviceOnly {
                return try onDeviceTranscription.get()
            }
            return try fallbackTranscription.get()
        }

        func ensureCallCount(for locale: Locale) async -> Int {
            ensureCalls.filter { $0 == locale.identifier }.count
        }

        func warmupCallCount(for locale: Locale) async -> Int {
            warmupCalls.filter { $0 == locale.identifier }.count
        }

        func transcribePathFlags() async -> [Bool] {
            transcribeCalls.map(\.onDeviceOnly)
        }

        func setEnsureDelayNanos(_ value: UInt64) {
            ensureDelayNanos = value
        }

        func setWarmupDelayNanos(_ value: UInt64) {
            warmupDelayNanos = value
        }

        func setFailEnsureLocales(_ locales: Set<String>) {
            failEnsureLocales = locales
        }

        func setOnDeviceTranscription(_ result: Result<String, Error>) {
            onDeviceTranscription = result
        }

        func setFallbackTranscription(_ result: Result<String, Error>) {
            fallbackTranscription = result
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    struct MockAuthorizationService: SpeechAuthorizationServing {
        var state: SpeechAuthorizationState = .authorized

        func authorizationStatus() async -> SpeechAuthorizationState { state }
        func requestAuthorization() async -> SpeechAuthorizationState { state }
    }

    @Test("warmup 后台执行不阻塞主链路")
    @MainActor
    func testBackgroundWarmupDoesNotBlockTranscribe() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let logger = MockLogger()
            let session = MockSpeechAnalyzerSession()
            await session.setEnsureDelayNanos(400_000_000)
            await session.setWarmupDelayNanos(200_000_000)
            let warmupService = SpeechTranscriberWarmupService(logger: logger, analyzerSession: session)
            let locale = Locale(identifier: "zh-CN")
            let fileURL = try makeAudioFixtureURL(name: #function)
            let transcriber = OnDeviceSpeechTranscriber(
                logger: logger,
                localeIdentifier: locale.identifier,
                authorizationService: MockAuthorizationService(),
                analyzerSession: session,
                warmupService: warmupService
            )

            let warmupStart = Date()
            let warmupStarted = await warmupService.warmup(locale: locale, waitForCompletion: false)
            let warmupElapsed = Date().timeIntervalSince(warmupStart)
            let transcribeStart = Date()
            let result = try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: 1_000)
            let transcribeElapsed = Date().timeIntervalSince(transcribeStart)
            let completedWarmup = await warmupService.warmup(locale: locale, waitForCompletion: true)

            #expect(warmupStarted == true)
            #expect(warmupElapsed < 0.1)
            #expect(result.text == "设备端结果")
            #expect(result.usedOnDevice == true)
            #expect(transcribeElapsed < 0.2)
            #expect(completedWarmup == true)
            #expect(await session.ensureCallCount(for: locale) == 1)
            #expect(await session.warmupCallCount(for: locale) == 1)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @Test("相同 locale 不重复 install")
    @MainActor
    func testSameLocaleDoesNotInstallTwice() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let logger = MockLogger()
            let session = MockSpeechAnalyzerSession()
            let warmupService = SpeechTranscriberWarmupService(logger: logger, analyzerSession: session)
            let locale = Locale(identifier: "zh-CN")

            let first = await warmupService.warmup(locale: locale, waitForCompletion: true)
            let second = await warmupService.warmup(locale: locale, waitForCompletion: true)
            let disposition = try await warmupService.prepareForRecognition(locale: locale)

            #expect(first == true)
            #expect(second == true)
            #expect(disposition == .readyFromCache)
            #expect(await session.ensureCallCount(for: locale) == 1)
            #expect(await session.warmupCallCount(for: locale) == 1)
        }
    }

    @Test("locale 切换时旧 cache 不命中新 locale")
    @MainActor
    func testLocaleSwitchInvalidatesCacheHit() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let logger = MockLogger()
            let session = MockSpeechAnalyzerSession()
            let warmupService = SpeechTranscriberWarmupService(logger: logger, analyzerSession: session)
            let zhLocale = Locale(identifier: "zh-CN")
            let enLocale = Locale(identifier: "en-US")

            let first = await warmupService.warmup(locale: zhLocale, waitForCompletion: true)
            let switched = try await warmupService.prepareForRecognition(locale: enLocale)
            let second = await warmupService.warmup(locale: enLocale, waitForCompletion: true)

            #expect(first == true)
            #expect(switched == .preparedSynchronously)
            #expect(second == true)
            #expect(await session.ensureCallCount(for: zhLocale) == 1)
            #expect(await session.ensureCallCount(for: enLocale) == 1)
            #expect(await session.warmupCallCount(for: zhLocale) == 1)
            #expect(await session.warmupCallCount(for: enLocale) == 1)
        }
    }

    @Test("warmup 失败不影响 fallback")
    @MainActor
    func testWarmupFailureDoesNotBlockFallback() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let logger = MockLogger()
            let locale = Locale(identifier: "zh-CN")
            let session = MockSpeechAnalyzerSession(supportedLocale: locale)
            await session.setFailEnsureLocales([locale.identifier])
            await session.setOnDeviceTranscription(.failure(MockSpeechAnalyzerSession.MockError.transcribeFailed))
            await session.setFallbackTranscription(.success("网络回退结果"))
            let warmupService = SpeechTranscriberWarmupService(logger: logger, analyzerSession: session)
            let transcriber = OnDeviceSpeechTranscriber(
                logger: logger,
                localeIdentifier: locale.identifier,
                authorizationService: MockAuthorizationService(),
                analyzerSession: session,
                warmupService: warmupService
            )
            let fileURL = try makeAudioFixtureURL(name: #function)

            let warmupSucceeded = await warmupService.warmup(locale: locale, waitForCompletion: true)
            let state = await warmupService.state
            let result = try await transcriber.transcribe(audioFileURL: fileURL, elapsedMs: 1_000)

            #expect(warmupSucceeded == false)
            #expect(state == .failed(locale, MockSpeechAnalyzerSession.MockError.ensureFailed))
            #expect(result.text == "网络回退结果")
            #expect(result.usedOnDevice == false)
            #expect(await session.transcribePathFlags() == [false])
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @Test("deallocate 只清理本地 cache 状态")
    @MainActor
    func testDeallocateClearsOnlyLocalCacheState() async throws {
        if #available(macOS 26.0, iOS 26.0, *) {
            let logger = MockLogger()
            let session = MockSpeechAnalyzerSession()
            let warmupService = SpeechTranscriberWarmupService(logger: logger, analyzerSession: session)
            let locale = Locale(identifier: "zh-CN")

            _ = await warmupService.warmup(locale: locale, waitForCompletion: true)
            await warmupService.deallocate(locale: locale)
            let state = await warmupService.state
            let disposition = try await warmupService.prepareForRecognition(locale: locale)

            #expect(state == .idle)
            #expect(disposition == .preparedSynchronously)
            #expect(await session.ensureCallCount(for: locale) == 2)
            #expect(await session.warmupCallCount(for: locale) == 2)
            #expect(logger.infoMessages.contains { $0.contains("clearing warmup cache") })
        }
    }

    private func makeAudioFixtureURL(name: String) throws -> URL {
        let sanitized = name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxlite-warmup-\(sanitized)-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        try Data("fixture".utf8).write(to: url)
        return url
    }
}
