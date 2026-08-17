// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HRVArtifactBench",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HRVArtifactBenchCore", targets: ["HRVArtifactBenchCore"]),
        .executable(name: "hrv-artifact-bench", targets: ["HRVArtifactBenchCLI"]),
    ],
    dependencies: [
        .package(path: "../../Packages/StrandAnalytics"),
    ],
    targets: [
        .target(
            name: "HRVArtifactBenchCore",
            dependencies: [
                .product(name: "StrandAnalytics", package: "StrandAnalytics"),
            ]
        ),
        .executableTarget(
            name: "HRVArtifactBenchCLI",
            dependencies: ["HRVArtifactBenchCore"]
        ),
        .testTarget(
            name: "HRVArtifactBenchCoreTests",
            dependencies: ["HRVArtifactBenchCore"]
        ),
    ]
)
