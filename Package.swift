// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxLite",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "VoxLiteFeature", targets: ["VoxLiteFeature"]),
        .executable(name: "VoxLiteApp", targets: ["VoxLiteApp"]),
        .executable(name: "VoxLiteSelfCheck", targets: ["VoxLiteSelfCheck"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "VoxLiteDomain"
        ),
        .target(
            name: "VoxLiteSystem",
            dependencies: ["VoxLiteDomain"]
        ),
        .target(
            name: "VoxLiteInput",
            dependencies: ["VoxLiteDomain", "VoxLiteSystem"]
        ),
        .target(
            name: "VoxLiteCore",
            dependencies: ["VoxLiteDomain", "VoxLiteSystem"]
        ),
        .target(
            name: "VoxLiteOutput",
            dependencies: ["VoxLiteDomain", "VoxLiteSystem"]
        ),
        .target(
            name: "VoxLiteFeature",
            dependencies: [
                "VoxLiteDomain",
                "VoxLiteSystem",
                "VoxLiteInput",
                "VoxLiteCore",
                "VoxLiteOutput"
            ]
        ),
        .executableTarget(
            name: "VoxLiteApp",
            dependencies: [
                "VoxLiteDomain",
                "VoxLiteSystem",
                "VoxLiteInput",
                "VoxLiteCore",
                "VoxLiteOutput",
                "VoxLiteFeature"
            ]
        ),
        .executableTarget(
            name: "VoxLiteSelfCheck",
            dependencies: [
                "VoxLiteDomain",
                "VoxLiteCore",
                "VoxLiteInput",
                "VoxLiteOutput",
                "VoxLiteSystem",
                "VoxLiteFeature"
            ]
        ),
        .testTarget(
            name: "VoxLiteTests",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
                "VoxLiteDomain",
                "VoxLiteCore",
                "VoxLiteInput",
                "VoxLiteOutput",
                "VoxLiteSystem",
                "VoxLiteFeature"
            ]
        ),
        .testTarget(
            name: "SystemTests",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
                "VoxLiteDomain",
                "VoxLiteCore",
                "VoxLiteSystem"
            ]
        ),
        .testTarget(
            name: "InputLayerTests",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
                "VoxLiteDomain",
                "VoxLiteInput"
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
                "VoxLiteDomain",
                "VoxLiteCore"
            ]
        )
    ]
)
