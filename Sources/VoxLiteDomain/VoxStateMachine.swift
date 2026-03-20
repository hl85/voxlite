import Foundation

public final class VoxStateMachine: StateStore, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var current: VoxState = .idle

    public init() {}

    public func transition(to next: VoxState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let allowed = canTransition(from: current, to: next)
        guard allowed else { return false }
        current = next
        return true
    }

    private func canTransition(from: VoxState, to: VoxState) -> Bool {
        switch (from, to) {
        case (.idle, .recording), (.idle, .failed):
            return true
        case (.recording, .processing), (.recording, .idle), (.recording, .failed):
            return true
        case (.processing, .injecting), (.processing, .failed):
            return true
        case (.injecting, .done), (.injecting, .failed):
            return true
        case (.done, .idle):
            return true
        case (.failed, .idle):
            return true
        default:
            return false
        }
    }
}
