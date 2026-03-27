import XCTest

final class VoxLiteUITests: UITestBase {
    func test_uiTestBundle_isPresent() throws {
        throw XCTSkip("当前环境缺少完整 Xcode UI Test 运行时，仅保留 bundle 占位。")
    }
}
