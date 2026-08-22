// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cobra",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CobraCore", targets: ["CobraCore"]),
        .executable(name: "CobraMac", targets: ["CobraMac"]),
    ],
    targets: [
        .target(
            name: "CobraCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CobraMac",
            dependencies: ["CobraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
