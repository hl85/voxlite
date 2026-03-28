import Darwin
import Foundation

public struct RuntimeResourceSnapshot: Sendable {
    public let cpuUsagePercent: Double
    public let memoryMB: Double
    public let timestamp: Date

    public init(
        cpuUsagePercent: Double,
        memoryMB: Double,
        timestamp: Date = Date()
    ) {
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryMB = memoryMB
        self.timestamp = timestamp
    }
}

/// Represents the current resource pressure level
public enum ResourcePressureLevel: Equatable, Sendable {
    /// Normal operation - no pressure
    case normal
    /// Elevated pressure - consider releasing non-critical resources
    case elevated
    /// Critical pressure - must release resources immediately
    case critical

    public var shouldReleaseAssets: Bool {
        switch self {
        case .normal:
            return false
        case .elevated, .critical:
            return true
        }
    }

    public var shouldReleaseAnalyzer: Bool {
        switch self {
        case .normal, .elevated:
            return false
        case .critical:
            return true
        }
    }

    public var description: String {
        switch self {
        case .normal:
            return "正常"
        case .elevated:
            return "升高"
        case .critical:
            return "临界"
        }
    }
}

/// Configuration for resource pressure detection
public struct ResourcePressureConfiguration: Equatable, Sendable {
    /// CPU usage threshold for elevated pressure (percentage)
    public let cpuElevatedThreshold: Double
    /// CPU usage threshold for critical pressure (percentage)
    public let cpuCriticalThreshold: Double
    /// Memory usage threshold for elevated pressure (MB)
    public let memoryElevatedThresholdMB: Double
    /// Memory usage threshold for critical pressure (MB)
    public let memoryCriticalThresholdMB: Double

    public init(
        cpuElevatedThreshold: Double = 30.0,
        cpuCriticalThreshold: Double = 60.0,
        memoryElevatedThresholdMB: Double = 300.0,
        memoryCriticalThresholdMB: Double = 500.0
    ) {
        self.cpuElevatedThreshold = cpuElevatedThreshold
        self.cpuCriticalThreshold = cpuCriticalThreshold
        self.memoryElevatedThresholdMB = memoryElevatedThresholdMB
        self.memoryCriticalThresholdMB = memoryCriticalThresholdMB
    }

    /// Default configuration for Apple Silicon
    public static let `default` = ResourcePressureConfiguration()

    /// Conservative configuration for Intel/constrained devices
    public static let conservative = ResourcePressureConfiguration(
        cpuElevatedThreshold: 20.0,
        cpuCriticalThreshold: 40.0,
        memoryElevatedThresholdMB: 200.0,
        memoryCriticalThresholdMB: 350.0
    )
}

public final class PerformanceSampler: @unchecked Sendable {
    private let pressureConfiguration: ResourcePressureConfiguration

    public init(pressureConfiguration: ResourcePressureConfiguration = .default) {
        self.pressureConfiguration = pressureConfiguration
    }

    public func sample() -> RuntimeResourceSnapshot {
        RuntimeResourceSnapshot(
            cpuUsagePercent: currentCPUUsage(),
            memoryMB: currentMemoryMB(),
            timestamp: Date()
        )
    }

    /// Evaluate the resource pressure level from the current snapshot
    public func evaluatePressure(snapshot: RuntimeResourceSnapshot) -> ResourcePressureLevel {
        var elevatedCount = 0
        var criticalCount = 0

        // Check CPU pressure
        if snapshot.cpuUsagePercent >= pressureConfiguration.cpuCriticalThreshold {
            criticalCount += 1
        } else if snapshot.cpuUsagePercent >= pressureConfiguration.cpuElevatedThreshold {
            elevatedCount += 1
        }

        // Check memory pressure
        if snapshot.memoryMB >= pressureConfiguration.memoryCriticalThresholdMB {
            criticalCount += 1
        } else if snapshot.memoryMB >= pressureConfiguration.memoryElevatedThresholdMB {
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

    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kern: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kern == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    private func currentCPUUsage() -> Double {
        var threads: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &threadCount) == KERN_SUCCESS, let threads else {
            return 0
        }

        var totalUsage: Double = 0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += (Double(info.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
            }
        }

        let deallocSize = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), deallocSize)
        return totalUsage
    }
}
