import Foundation

// MARK: - Device Tier Classification

/// Represents the hardware tier of the current device
public enum DeviceTier: Equatable, Sendable {
    /// Apple Silicon (M1, M2, M3, etc.) - Full retention capabilities
    case appleSilicon
    /// Intel Mac or resource-constrained platform - Limited retention
    case intelOrConstrained
    /// Unsupported or unknown platform - Minimal retention
    case unsupported

    public var retentionCapability: RetentionCapability {
        switch self {
        case .appleSilicon:
            return .full
        case .intelOrConstrained:
            return .limited
        case .unsupported:
            return .minimal
        }
    }
}

/// The retention capability level for a device tier
public enum RetentionCapability: Equatable, Sendable {
    /// Full retention - keep warmup assets and analyzer ready
    case full
    /// Limited retention - release assets under pressure
    case limited
    /// Minimal retention - aggressive release
    case minimal
}

// MARK: - Retention Decision

/// The decision made by the retention policy
public enum RetentionDecision: Equatable, Sendable {
    /// Keep all resources (warmup assets and analyzer)
    case retainAll
    /// Release warmup assets but keep analyzer
    case releaseAssetsOnly
    /// Release both assets and analyzer (full deallocate)
    case releaseAll

    public var shouldReleaseAssets: Bool {
        switch self {
        case .retainAll:
            return false
        case .releaseAssetsOnly, .releaseAll:
            return true
        }
    }

    public var shouldReleaseAnalyzer: Bool {
        switch self {
        case .retainAll, .releaseAssetsOnly:
            return false
        case .releaseAll:
            return true
        }
    }
}

// MARK: - Retention Policy Configuration

/// Configuration for the model retention policy
public struct RetentionPolicyConfiguration: Equatable, Sendable {
    /// CPU usage threshold for elevated pressure (percentage)
    public let cpuElevatedThreshold: Double
    /// CPU usage threshold for critical pressure (percentage)
    public let cpuCriticalThreshold: Double
    /// Memory usage threshold for elevated pressure (MB)
    public let memoryElevatedThresholdMB: Double
    /// Memory usage threshold for critical pressure (MB)
    public let memoryCriticalThresholdMB: Double
    /// Whether to enable retention policy on Intel/constrained devices
    public let enableOnConstrainedDevices: Bool
    /// Inactivity timeout before releasing assets (seconds), 0 = never
    public let assetReleaseTimeoutSeconds: Double
    /// Inactivity timeout before releasing analyzer (seconds), 0 = never
    public let analyzerReleaseTimeoutSeconds: Double

    public init(
        cpuElevatedThreshold: Double = 30.0,
        cpuCriticalThreshold: Double = 60.0,
        memoryElevatedThresholdMB: Double = 300.0,
        memoryCriticalThresholdMB: Double = 500.0,
        enableOnConstrainedDevices: Bool = true,
        assetReleaseTimeoutSeconds: Double = 300.0,
        analyzerReleaseTimeoutSeconds: Double = 600.0
    ) {
        self.cpuElevatedThreshold = cpuElevatedThreshold
        self.cpuCriticalThreshold = cpuCriticalThreshold
        self.memoryElevatedThresholdMB = memoryElevatedThresholdMB
        self.memoryCriticalThresholdMB = memoryCriticalThresholdMB
        self.enableOnConstrainedDevices = enableOnConstrainedDevices
        self.assetReleaseTimeoutSeconds = assetReleaseTimeoutSeconds
        self.analyzerReleaseTimeoutSeconds = analyzerReleaseTimeoutSeconds
    }

    /// Default configuration optimized for Apple Silicon
    public static let `default` = RetentionPolicyConfiguration()

    /// Conservative configuration for Intel/constrained devices
    public static let conservative = RetentionPolicyConfiguration(
        cpuElevatedThreshold: 20.0,
        cpuCriticalThreshold: 40.0,
        memoryElevatedThresholdMB: 200.0,
        memoryCriticalThresholdMB: 350.0,
        enableOnConstrainedDevices: true,
        assetReleaseTimeoutSeconds: 180.0,
        analyzerReleaseTimeoutSeconds: 300.0
    )
}

// MARK: - Device Tier Detection

/// Detects the device tier of the current hardware
public enum DeviceTierDetector {
    /// Detect the current device tier
    public static func detect() -> DeviceTier {
        #if os(macOS)
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        
        guard platformExpert != 0 else {
            return .unsupported
        }
        
        guard let modelData = IORegistryEntryCreateCFProperty(platformExpert, "model" as CFString, kCFAllocatorDefault, 0),
              let model = modelData.takeRetainedValue() as? Data,
              let modelString = String(data: model, encoding: .utf8) else {
            return .unsupported
        }
        
        // Check for Apple Silicon (M-series chips)
        // Mac models with Apple Silicon start with "Mac" followed by specific patterns
        // Mac13,1+ are generally Apple Silicon
        // Mac14,x are Apple Silicon
        // Mac15,x are Apple Silicon (M3 series)
        if modelString.contains("MacBookAir") || modelString.contains("MacBookPro") || modelString.contains("Mac14") || modelString.contains("Mac15") || modelString.contains("Mac16") {
            // Check for Intel patterns in model identifier
            if modelString.contains("Intel") || modelString.contains("x86") {
                return .intelOrConstrained
            }
            // Newer Mac models (2020+) without Intel indicators are Apple Silicon
            return .appleSilicon
        }
        
        // Check for Mac mini, iMac, Mac Studio, Mac Pro
        if modelString.contains("Mac13") || modelString.contains("Mac14") || modelString.contains("Mac15") || modelString.contains("Mac16") {
            // These are Apple Silicon models (Mac Studio, Mac Pro, newer iMac/Mac mini)
            return .appleSilicon
        }
        
        // Older Mac models (pre-2020) are likely Intel
        if modelString.hasPrefix("Mac") {
            let components = modelString.components(separatedBy: CharacterSet.decimalDigits.inverted)
            if let majorVersionString = components.first(where: { !$0.isEmpty }),
               let majorVersion = Int(majorVersionString) {
                // Mac models before Mac13,x are generally Intel
                if majorVersion < 13 {
                    return .intelOrConstrained
                }
            }
        }
        
        // Default to Intel for unknown models to be safe
        return .intelOrConstrained
        #else
        return .unsupported
        #endif
    }
}

import IOKit

// MARK: - Model Retention Policy

/// The main retention policy implementation
public final class ModelRetentionPolicy: Sendable {
    private let configuration: RetentionPolicyConfiguration
    private let deviceTier: DeviceTier

    public init(
        configuration: RetentionPolicyConfiguration = .default,
        deviceTier: DeviceTier? = nil
    ) {
        self.configuration = configuration
        self.deviceTier = deviceTier ?? DeviceTierDetector.detect()
    }

    /// The detected device tier
    public var currentDeviceTier: DeviceTier { deviceTier }

    /// Evaluate the current resource snapshot and make a retention decision
    public func evaluate(snapshot: RuntimeResourceSnapshot) -> RetentionDecision {
        let pressure = evaluatePressure(snapshot: snapshot)
        return makeDecision(pressure: pressure)
    }

    /// Evaluate the resource pressure level from a snapshot
    private func evaluatePressure(snapshot: RuntimeResourceSnapshot) -> ResourcePressureLevel {
        var elevatedCount = 0
        var criticalCount = 0

        // Check CPU pressure
        if snapshot.cpuUsagePercent >= configuration.cpuCriticalThreshold {
            criticalCount += 1
        } else if snapshot.cpuUsagePercent >= configuration.cpuElevatedThreshold {
            elevatedCount += 1
        }

        // Check memory pressure
        if snapshot.memoryMB >= configuration.memoryCriticalThresholdMB {
            criticalCount += 1
        } else if snapshot.memoryMB >= configuration.memoryElevatedThresholdMB {
            elevatedCount += 1
        }

        // Determine pressure level
        if criticalCount >= 1 {
            return .critical
        } else if elevatedCount >= 1 {
            return .elevated
        } else {
            return .normal
        }
    }

    /// Make a retention decision based on pressure level and device tier
    private func makeDecision(pressure: ResourcePressureLevel) -> RetentionDecision {
        let capability = deviceTier.retentionCapability

        // Handle unsupported platforms - always release aggressively
        guard capability != .minimal else {
            return .releaseAll
        }

        // Critical pressure always triggers release based on capability
        if pressure == .critical {
            switch capability {
            case .full:
                // Apple Silicon: release assets but keep analyzer for quick recovery
                return .releaseAssetsOnly
            case .limited, .minimal:
                // Intel/Constrained: full release to relieve pressure
                return .releaseAll
            }
        }

        // Elevated pressure triggers conditional release
        if pressure == .elevated {
            switch capability {
            case .full:
                // Apple Silicon: can retain but monitor closely
                return .retainAll
            case .limited:
                // Intel/Constrained: release assets to prevent escalation
                return .releaseAssetsOnly
            case .minimal:
                return .releaseAll
            }
        }

        // Normal pressure - retain based on capability
        switch capability {
        case .full, .limited:
            return .retainAll
        case .minimal:
            return .releaseAssetsOnly
        }
    }

    /// Check if retention is enabled for the current device
    public var isRetentionEnabled: Bool {
        switch deviceTier {
        case .appleSilicon:
            return true
        case .intelOrConstrained:
            return configuration.enableOnConstrainedDevices
        case .unsupported:
            return false
        }
    }

    /// Get the recommended configuration for the current device
    public var recommendedConfiguration: RetentionPolicyConfiguration {
        switch deviceTier {
        case .appleSilicon:
            return .default
        case .intelOrConstrained, .unsupported:
            return .conservative
        }
    }
}

// MARK: - Convenience Extensions

extension RetentionDecision {
    /// Human-readable description of the decision
    public var description: String {
        switch self {
        case .retainAll:
            return "保留所有资源"
        case .releaseAssetsOnly:
            return "释放资产但保留分析器"
        case .releaseAll:
            return "释放所有资源"
        }
    }
}

extension DeviceTier {
    /// Human-readable description of the device tier
    public var description: String {
        switch self {
        case .appleSilicon:
            return "Apple Silicon"
        case .intelOrConstrained:
            return "Intel/受限平台"
        case .unsupported:
            return "不支持的平台"
        }
    }
}
