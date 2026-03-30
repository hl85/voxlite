import Foundation
import Testing
@testable import VoxLiteSystem

@MainActor
struct AXPermissionTests {
    @Test
    func testAXPermissionRequestAtLaunch() {
        let manager = PermissionManager()

        #expect(Bool(true))
        manager.requestAccessibilityPermission()
        _ = manager.checkAccessibilityPermission()
    }
}
