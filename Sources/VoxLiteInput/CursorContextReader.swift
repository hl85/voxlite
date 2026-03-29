import Foundation
import VoxLiteDomain

public final class AXCursorContextReader: CursorContextReading, @unchecked Sendable {

    private let maxContextLength = 500
    private let contextLineRadius = 3

    public init() {}

    public func readContext() async throws -> CursorContext? {
        return nil
    }
}
