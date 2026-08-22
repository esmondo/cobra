// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cobra",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CobraCore", targets: ["CobraCore"]),
        .executable(name: "CobraMac", targets: ["CobraMac"]),
        .executable(name: "CobraProbe", targets: ["CobraProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .target(
            name: "CobraCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CobraProbe",
            dependencies: ["CobraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CobraMac",
            dependencies: ["CobraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CobraCoreTests",
            dependencies: ["CobraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
