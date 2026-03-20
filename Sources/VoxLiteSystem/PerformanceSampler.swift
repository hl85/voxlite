import Darwin
import Foundation

public struct RuntimeResourceSnapshot: Sendable {
    public let cpuUsagePercent: Double
    public let memoryMB: Double
    public let timestamp: Date
}

public final class PerformanceSampler {
    public init() {}

    public func sample() -> RuntimeResourceSnapshot {
        RuntimeResourceSnapshot(
            cpuUsagePercent: currentCPUUsage(),
            memoryMB: currentMemoryMB(),
            timestamp: Date()
        )
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
