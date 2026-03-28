import Foundation
import Speech
import VoxLiteDomain
import VoxLiteSystem

/// Warmup/Readiness 模式服务
/// 参考 WWDC 2025 SpeechAnalyzer 演示实现
/// 提供 locale-aware 的预热和资源管理
@available(macOS 26.0, iOS 26.0, *)
public actor SpeechTranscriberWarmupService {
    
    // MARK: - Types
    
    /// Warmup 状态
    public enum WarmupState: Sendable, Equatable {
        case idle
        case warmingUp(Locale)
        case ready(Locale)
        case failed(Locale, Error)

        public static func == (lhs: WarmupState, rhs: WarmupState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.warmingUp(let lhsLocale), .warmingUp(let rhsLocale)):
                return lhsLocale.identifier == rhsLocale.identifier
            case (.ready(let lhsLocale), .ready(let rhsLocale)):
                return lhsLocale.identifier == rhsLocale.identifier
            case (.failed(let lhsLocale, let lhsError), .failed(let rhsLocale, let rhsError)):
                return lhsLocale.identifier == rhsLocale.identifier && String(describing: lhsError) == String(describing: rhsError)
            default:
                return false
            }
        }
        
        public var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
        
        public var locale: Locale? {
            switch self {
            case .warmingUp(let locale), .ready(let locale), .failed(let locale, _):
                return locale
            default:
                return nil
            }
        }
    }
    
    /// 缓存条目
    private struct CacheEntry: Sendable {
        let locale: Locale
        let isInstalled: Bool
        let timestamp: Date
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300 // 5分钟过期
        }
    }

    public enum PreparationDisposition: Sendable, Equatable {
        case readyFromCache
        case preparedSynchronously
        case backgroundWarmupInProgress
    }

    private struct WarmupTaskRecord: Sendable {
        let token: UUID
        let task: Task<Bool, Never>
    }
    
    // MARK: - Properties
    
    private var currentState: WarmupState = .idle
    private var localeCache: [String: CacheEntry] = [:]
    private let logger: LoggerServing
    private let analyzerSession: SpeechAnalyzerSessionServing
    private var warmupTasks: [String: WarmupTaskRecord] = [:]
    
    /// 当前 warmup 状态（公共接口）
    public var state: WarmupState { currentState }
    
    // MARK: - Initialization
    
    public init(
        logger: LoggerServing,
        analyzerSession: SpeechAnalyzerSessionServing = SystemSpeechAnalyzerSession()
    ) {
        self.logger = logger
        self.analyzerSession = analyzerSession
    }
    
    // MARK: - Public Methods
    
    /// 执行 warmup - 异步非阻塞，失败不抛出
    /// - Parameters:
    ///   - locale: 目标 locale
    ///   - waitForCompletion: 是否等待完成（用于后台预热）
    /// - Returns: 是否成功
    @discardableResult
    public func warmup(locale: Locale, waitForCompletion: Bool = false) async -> Bool {
        if isCacheHit(locale: locale) {
            logger.info("warmup cache hit locale=\(locale.identifier)")
            currentState = .ready(locale)
            return true
        }

        if let existingTask = warmupTasks[locale.identifier]?.task {
            logger.info("warmup already in progress locale=\(locale.identifier)")
            return waitForCompletion ? await existingTask.value : true
        }

        currentState = .warmingUp(locale)
        logger.info("warmup starting locale=\(locale.identifier)")

        let token = UUID()
        let warmupTask = Task { [weak self] () -> Bool in
            guard let self else { return false }
            do {
                try await self.performWarmup(for: locale)
                await self.finishWarmup(locale: locale, token: token, result: .success(()))
                return true
            } catch {
                await self.finishWarmup(locale: locale, token: token, result: .failure(error))
                return false
            }
        }
        warmupTasks[locale.identifier] = WarmupTaskRecord(token: token, task: warmupTask)

        if waitForCompletion {
            return await warmupTask.value
        } else {
            return true
        }
    }

    public func prepareForRecognition(locale: Locale) async throws -> PreparationDisposition {
        if isCacheHit(locale: locale) {
            logger.info("warmup cache hit locale=\(locale.identifier)")
            currentState = .ready(locale)
            return .readyFromCache
        }

        if warmupTasks[locale.identifier] != nil {
            logger.info("warmup background in progress locale=\(locale.identifier)")
            return .backgroundWarmupInProgress
        }

        currentState = .warmingUp(locale)
        logger.info("warmup foreground prepare locale=\(locale.identifier)")

        do {
            try await performWarmup(for: locale)
            updateCache(locale: locale, isInstalled: true)
            transitionToReady(locale: locale)
            return .preparedSynchronously
        } catch {
            updateCache(locale: locale, isInstalled: false)
            transitionToFailed(locale: locale, error: error)
            throw error
        }
    }
    
    /// 检查指定 locale 是否已 ready
    public func isReady(for locale: Locale) -> Bool {
        if case .ready(let readyLocale) = currentState {
            return readyLocale.identifier == locale.identifier
        }
        return false
    }
    
    public func deallocate(locale: Locale) async {
        logger.info("clearing warmup cache locale=\(locale.identifier)")

        warmupTasks[locale.identifier]?.task.cancel()
        warmupTasks.removeValue(forKey: locale.identifier)
        localeCache.removeValue(forKey: locale.identifier)

        if currentState.locale?.identifier == locale.identifier {
            currentState = .idle
        }
    }
    
    /// 清除所有缓存和状态
    public func reset() async {
        logger.info("resetting warmup service")
        for record in warmupTasks.values {
            record.task.cancel()
        }
        warmupTasks.removeAll()
        localeCache.removeAll()
        currentState = .idle
    }
    
    // MARK: - Private Methods
    
    /// 执行实际的 warmup 逻辑
    private func performWarmup(for locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw WarmupError.transcriberUnavailable
        }
        logger.info("warmup ensuring assets locale=\(locale.identifier)")
        try await analyzerSession.ensureAssets(for: locale, onDeviceOnly: true)
        try Task.checkCancellation()
        logger.info("warmup creating analyzer locale=\(locale.identifier)")
        try await analyzerSession.warmupAnalyzer(for: locale, onDeviceOnly: true)
    }
    
    /// 检查缓存命中
    private func isCacheHit(locale: Locale) -> Bool {
        guard let entry = localeCache[locale.identifier] else { return false }
        return entry.isInstalled && !entry.isExpired
    }
    
    /// 更新缓存
    private func updateCache(locale: Locale, isInstalled: Bool) {
        localeCache[locale.identifier] = CacheEntry(
            locale: locale,
            isInstalled: isInstalled,
            timestamp: Date()
        )
    }

    private func finishWarmup(locale: Locale, token: UUID, result: Result<Void, Error>) {
        guard let record = warmupTasks[locale.identifier], record.token == token else {
            return
        }
        warmupTasks.removeValue(forKey: locale.identifier)
        switch result {
        case .success:
            updateCache(locale: locale, isInstalled: true)
            transitionToReady(locale: locale)
        case .failure(let error):
            if error is CancellationError {
                logger.info("warmup cancelled locale=\(locale.identifier)")
                if currentState.locale?.identifier == locale.identifier {
                    currentState = .idle
                }
                return
            }
            updateCache(locale: locale, isInstalled: false)
            transitionToFailed(locale: locale, error: error)
        }
    }
    
    /// 状态转换：ready
    private func transitionToReady(locale: Locale) {
        logger.info("warmup completed successfully locale=\(locale.identifier)")
        currentState = .ready(locale)
    }
    
    /// 状态转换：failed
    private func transitionToFailed(locale: Locale, error: Error) {
        logger.warn("warmup failed locale=\(locale.identifier) error=\(error.localizedDescription)")
        currentState = .failed(locale, error)
    }
}

// MARK: - WarmupError

@available(macOS 26.0, iOS 26.0, *)
public enum WarmupError: Error, Sendable {
    case transcriberUnavailable
    case assetInstallationFailed(String)
    case timeout
}
