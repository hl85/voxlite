import Foundation
import VoxLiteDomain

@MainActor
public final class VoicePipeline {
    public enum Stage: String, CaseIterable, Equatable, Sendable {
        case assetCheck = "asset-check"
        case assetInstall = "asset-install"
        case analyzerCreate = "analyzer-create"
        case analyzerWarmup = "analyzer-warmup"
        case transcribe
        case clean
        case inject

        public var metricEvent: String {
            "pipeline.stage.\(rawValue)"
        }
    }

    public enum StagePhase: String, Equatable, Sendable {
        case started
        case completed
    }

    public struct StageEvent: Equatable, Sendable {
        public let stage: Stage
        public let phase: StagePhase
        public let success: Bool?
        public let errorCode: VoxErrorCode?
        public let latencyMs: Int?

        public init(stage: Stage, phase: StagePhase, success: Bool? = nil, errorCode: VoxErrorCode? = nil, latencyMs: Int? = nil) {
            self.stage = stage
            self.phase = phase
            self.success = success
            self.errorCode = errorCode
            self.latencyMs = latencyMs
        }
    }

    public typealias StageObserver = @MainActor (StageEvent) -> Void

    private let stateMachine: StateStore
    private let audioCapture: AudioCaptureServing
    private let transcriber: SpeechTranscribing
    private let contextResolver: ContextResolving
    private let cleaner: TextCleaning
    private let injector: TextInjecting
    private let permissions: PermissionManaging
    private let logger: LoggerServing
    private let metrics: MetricsServing
    private let retryPolicy: RetryPolicy

    public var stageObserver: StageObserver?

    public init(
        stateMachine: StateStore,
        audioCapture: AudioCaptureServing,
        transcriber: SpeechTranscribing,
        contextResolver: ContextResolving,
        cleaner: TextCleaning,
        injector: TextInjecting,
        permissions: PermissionManaging,
        logger: LoggerServing,
        metrics: MetricsServing,
        retryPolicy: RetryPolicy = .m2Default
    ) {
        self.stateMachine = stateMachine
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.contextResolver = contextResolver
        self.cleaner = cleaner
        self.injector = injector
        self.permissions = permissions
        self.logger = logger
        self.metrics = metrics
        self.retryPolicy = retryPolicy
    }

    public func startRecording() throws -> UUID {
        logger.info("pipeline startRecording begin")
        let snapshot = permissions.currentPermissionSnapshot()
        guard snapshot.allGranted else {
            logger.warn("pipeline startRecording denied permissions mic=\(snapshot.microphoneGranted) speech=\(snapshot.speechRecognitionGranted) ax=\(snapshot.accessibilityGranted)")
            _ = stateMachine.transition(to: .failed)
            if !snapshot.microphoneGranted {
                throw VoxErrorCode.permissionMicrophoneDenied
            }
            if !snapshot.accessibilityGranted {
                throw VoxErrorCode.permissionAccessibilityDenied
            }
            if !snapshot.speechRecognitionGranted {
                throw VoxErrorCode.permissionSpeechDenied
            }
            throw VoxErrorCode.permissionDenied
        }
        guard stateMachine.transition(to: .recording) else {
            logger.warn("pipeline startRecording state transition rejected from current state")
            throw VoxErrorCode.recordingUnavailable
        }
        do {
            let id = try audioCapture.startRecording()
            logger.info("pipeline startRecording success session=\(id.uuidString)")
            return id
        } catch let error as VoxErrorCode {
            logger.error("pipeline startRecording failed error=\(error.rawValue)")
            _ = stateMachine.transition(to: .failed)
            _ = stateMachine.transition(to: .idle)
            throw error
        } catch {
            logger.error("pipeline startRecording failed unknown error")
            _ = stateMachine.transition(to: .failed)
            _ = stateMachine.transition(to: .idle)
            throw VoxErrorCode.recordingUnavailable
        }
    }

    public func stopRecordingAndProcess(sessionId: UUID) async throws -> ProcessResult {
        let processStart = Date()
        logger.info("pipeline process begin session=\(sessionId.uuidString)")
        guard stateMachine.transition(to: .processing) else {
            logger.warn("pipeline process state transition rejected from current state")
            throw VoxErrorCode.unknown
        }

        let audioStopStart = Date()
        logger.debug("pipeline stage audio-stop begin")
        let audio = try audioCapture.stopRecording(sessionId: sessionId)
        let audioStopMs = Int(Date().timeIntervalSince(audioStopStart) * 1000)
        logger.debug("pipeline stage audio-stop done bytes=\(audio.count) latency=\(audioStopMs)ms")
        metrics.record(event: "pipeline.stage.audio-stop", success: true, errorCode: nil, latencyMs: audioStopMs)
        let context = contextResolver.resolveContext()

        var reportedStages = Set<Stage>()
        let previousTranscriberObserver = installTranscriberStageObserver { [weak self] event in
            guard let self else { return }
            self.publishStage(event)
            if event.phase == .completed {
                reportedStages.insert(event.stage)
                if let success = event.success {
                    self.metrics.record(
                        event: event.stage.metricEvent,
                        success: success,
                        errorCode: event.errorCode,
                        latencyMs: event.latencyMs ?? 0
                    )
                }
            }
        }
        defer { restoreTranscriberStageObserver(previousTranscriberObserver) }

        publishStage(.init(stage: .transcribe, phase: .started))
        logger.debug("pipeline stage transcribe begin")
        let parsedAudio = try parseAudioPayload(audio)
        defer { try? FileManager.default.removeItem(at: parsedAudio.url) }
        let transcription: SpeechTranscription
        do {
            transcription = try await transcriber.transcribe(
                audioFileURL: parsedAudio.url,
                elapsedMs: parsedAudio.elapsedMs
            )
        } catch let error as SpeechTranscriptionError {
            let mappedError = mapTranscriptionError(error)
            publishStage(.init(stage: .transcribe, phase: .completed, success: false, errorCode: mappedError, latencyMs: nil))
            metrics.record(event: Stage.transcribe.metricEvent, success: false, errorCode: mappedError, latencyMs: 0)
            throw mapTranscriptionError(error)
        } catch {
            publishStage(.init(stage: .transcribe, phase: .completed, success: false, errorCode: .transcriptionUnavailable, latencyMs: nil))
            metrics.record(event: Stage.transcribe.metricEvent, success: false, errorCode: .transcriptionUnavailable, latencyMs: 0)
            throw VoxErrorCode.transcriptionUnavailable
        }
        let transcript = TranscriptResult(
            text: transcription.text,
            success: true,
            errorCode: nil,
            latencyMs: transcription.latencyMs
        )
        logger.info("pipeline stage transcribe done success=true error=none latency=\(transcript.latencyMs)ms textLen=\(transcript.text.count)")
        if reportedStages.contains(.transcribe) == false {
            publishStage(.init(stage: .transcribe, phase: .completed, success: true, errorCode: nil, latencyMs: transcript.latencyMs))
            metrics.record(event: Stage.transcribe.metricEvent, success: true, errorCode: nil, latencyMs: transcript.latencyMs)
        }
        guard transcript.latencyMs <= retryPolicy.timeoutMs else {
            _ = stateMachine.transition(to: .failed)
            metrics.record(event: "pipeline.timeout", success: false, errorCode: .timeout, latencyMs: transcript.latencyMs)
            throw VoxErrorCode.timeout
        }

        publishStage(.init(stage: .clean, phase: .started))
        var clean = await cleaner.cleanText(transcript: transcript.text, context: context)
        logger.info("pipeline stage clean done success=\(clean.success) latency=\(clean.latencyMs)ms usedFallback=\(clean.usedFallback)")
        publishStage(.init(stage: .clean, phase: .completed, success: clean.success, errorCode: clean.errorCode, latencyMs: clean.latencyMs))
        metrics.record(event: Stage.clean.metricEvent, success: clean.success, errorCode: clean.errorCode, latencyMs: clean.latencyMs)
        if clean.latencyMs > retryPolicy.timeoutMs || !clean.success {
            clean = CleanResult(
                cleanText: transcript.text,
                confidence: 0.55,
                styleTag: "仅转录",
                usedFallback: true,
                success: true,
                errorCode: nil,
                latencyMs: clean.latencyMs
            )
            metrics.record(event: "pipeline.clean.fallback", success: true, errorCode: nil, latencyMs: clean.latencyMs)
            logger.warn("clean fallback to transcript")
        }

        let inject = try await executeWithRetry(maxRetry: retryPolicy.maxRetries) {
            guard Int(Date().timeIntervalSince(processStart) * 1000) <= retryPolicy.timeoutMs else {
                throw VoxErrorCode.timeout
            }
            if stateMachine.current != .injecting {
                guard stateMachine.transition(to: .injecting) else {
                    logger.warn("pipeline stage inject state transition rejected")
                    throw VoxErrorCode.injectionFailed
                }
            }
            publishStage(.init(stage: .inject, phase: .started))
            logger.debug("pipeline stage inject begin")
            let inject = injector.injectText(clean.cleanText)
            logger.info("pipeline stage inject done success=\(inject.success) error=\(inject.errorCode?.rawValue ?? "none") latency=\(inject.latencyMs)ms fallback=\(inject.usedClipboardFallback)")
            publishStage(.init(stage: .inject, phase: .completed, success: inject.success, errorCode: inject.errorCode, latencyMs: inject.latencyMs))
            metrics.record(event: Stage.inject.metricEvent, success: inject.success, errorCode: inject.errorCode, latencyMs: inject.latencyMs)
            if !inject.success {
                throw inject.errorCode ?? .injectionFailed
            }
            if inject.latencyMs > retryPolicy.timeoutMs {
                logger.warn("pipeline stage inject exceeded timeout after side effect latency=\(inject.latencyMs)ms")
            }
            return inject
        }

        let total = Int(Date().timeIntervalSince(processStart) * 1000)
        _ = stateMachine.transition(to: .done)
        metrics.record(event: "pipeline.process", success: true, errorCode: nil, latencyMs: total)
        logger.info("pipeline done session=\(sessionId) audio-stop=\(audioStopMs)ms transcribe=\(transcript.latencyMs)ms clean=\(clean.latencyMs)ms inject=\(inject.latencyMs)ms total=\(total)ms")
        return ProcessResult(
            sessionId: sessionId,
            transcript: transcript,
            context: context,
            clean: clean,
            inject: inject,
            totalLatencyMs: total
        )
    }

    public func resetToIdle() {
        if stateMachine.current == .done || stateMachine.current == .failed {
            _ = stateMachine.transition(to: .idle)
        }
    }

    public func resetResources() async {
        if #available(macOS 26.0, iOS 26.0, *) {
            if let onDeviceTranscriber = transcriber as? OnDeviceSpeechTranscriber {
                await onDeviceTranscriber.resetResources()
            }
        }
    }

    public func percentileLatency(_ value: Double) -> Int? {
        metrics.percentile("pipeline.process", value)
    }

    public func percentileTranscribeLatency(_ value: Double) -> Int? {
        metrics.percentile(Stage.transcribe.metricEvent, value)
    }

    public func percentileCleanLatency(_ value: Double) -> Int? {
        metrics.percentile(Stage.clean.metricEvent, value)
    }

    public func percentileInjectLatency(_ value: Double) -> Int? {
        metrics.percentile(Stage.inject.metricEvent, value)
    }

    public func percentileLatency(for stage: Stage, value: Double) -> Int? {
        metrics.percentile(stage.metricEvent, value)
    }

    private func executeWithRetry<T>(maxRetry: Int, operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while attempt <= maxRetry {
            do {
                return try await operation()
            } catch let error as VoxErrorCode {
                logger.warn("pipeline retry caught error=\(error.rawValue) attempt=\(attempt) max=\(maxRetry)")
                if error == .transcriptionUnavailable || error == .permissionSpeechDenied {
                    logger.error("pipeline retry stopped for non-retriable transcribe error=\(error.rawValue)")
                    _ = stateMachine.transition(to: .failed)
                    throw error
                }
                if error == .timeout {
                    _ = stateMachine.transition(to: .failed)
                    metrics.record(event: "pipeline.timeout", success: false, errorCode: .timeout, latencyMs: attempt)
                    throw VoxErrorCode.timeout
                }
                attempt += 1
                if attempt > maxRetry {
                    logger.error("pipeline retry exhausted lastError=\(error.rawValue)")
                    _ = stateMachine.transition(to: .failed)
                    metrics.record(event: "pipeline.retry.exhausted", success: false, errorCode: .retryExhausted, latencyMs: attempt)
                    throw VoxErrorCode.retryExhausted
                }
            } catch {
                logger.error("pipeline retry caught unknown error attempt=\(attempt)")
                attempt += 1
            }
        }
        throw VoxErrorCode.retryExhausted
    }

    private func parseAudioPayload(_ audio: Data) throws -> (url: URL, elapsedMs: Int) {
        guard let payload = String(data: audio, encoding: .utf8) else {
            throw VoxErrorCode.transcriptionUnavailable
        }
        let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw VoxErrorCode.transcriptionUnavailable
        }
        let prefix = "file://"
        guard parts[0].hasPrefix(prefix) else {
            throw VoxErrorCode.transcriptionUnavailable
        }
        let path = String(parts[0].dropFirst(prefix.count))
        guard !path.isEmpty else {
            throw VoxErrorCode.transcriptionUnavailable
        }
        let elapsedMs = Int(parts[1]) ?? 0
        return (URL(fileURLWithPath: path), elapsedMs)
    }

    private func mapTranscriptionError(_ error: SpeechTranscriptionError) -> VoxErrorCode {
        switch error {
        case .permissionDenied:
            return .permissionSpeechDenied
        case .timedOut:
            return .timeout
        default:
            return .transcriptionUnavailable
        }
    }

    private func publishStage(_ event: StageEvent) {
        stageObserver?(event)
    }

    private func installTranscriberStageObserver(_ observer: @escaping StageObserver) -> StageObserver? {
        guard let transcriber = transcriber as? any VoicePipelineStageReporting else {
            return nil
        }
        let previous = transcriber.stageObserver
        transcriber.stageObserver = observer
        return previous
    }

    private func restoreTranscriberStageObserver(_ observer: StageObserver?) {
        guard let transcriber = transcriber as? any VoicePipelineStageReporting else {
            return
        }
        transcriber.stageObserver = observer
    }
}
