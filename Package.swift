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
                "VoxLiteDomain",
                "VoxLiteCore",
                "VoxLiteInput",
                "VoxLiteOutput",
                "VoxLiteSystem",
                "VoxLiteFeature"
            ]
        )
    ]
)
