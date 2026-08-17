// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RROrderCorpus",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RROrderCorpusCore", targets: ["RROrderCorpusCore"]),
        .executable(name: "rr-order-corpus", targets: ["RROrderCorpusCLI"]),
        .executable(name: "rr-order-summary", targets: ["RROrderSummaryCLI"]),
    ],
    dependencies: [
        .package(path: "../../Packages/WhoopProtocol"),
        .package(path: "../../Packages/WhoopStore"),
        .package(path: "../../Packages/StrandAnalytics"),
        // Match the exact version used by WhoopStore. This tool opens the production database read-only.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "6.29.3"),
    ],
    targets: [
        .target(
            name: "RROrderCorpusCore",
            dependencies: [
                "WhoopProtocol",
                "WhoopStore",
                "StrandAnalytics",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "RROrderCorpusCLI",
            dependencies: ["RROrderCorpusCore"]
        ),
        .executableTarget(
            name: "RROrderSummaryCLI",
            dependencies: ["RROrderCorpusCore"]
        ),
        .testTarget(
            name: "RROrderCorpusCoreTests",
            dependencies: [
                "RROrderCorpusCore",
                "WhoopProtocol",
                "WhoopStore",
                "StrandAnalytics",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
