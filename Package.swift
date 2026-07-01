// swift-tools-version: 5.9
import Foundation
import PackageDescription

let package = Package(
    name: "FastList",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "FastList", targets: ["FastList"])
    ],
    targets: [
        .target(name: "FastList", exclude: ["Example.swift"]),
        .executableTarget(name: "FastListDemo", dependencies: ["FastList"]),
        .testTarget(name: "FastListTests", dependencies: ["FastList"])
    ]
)

// Pull in swift-docc-plugin only when building documentation (set in the Pages CI job),
// so it stays out of consumers' dependency graphs.
if ProcessInfo.processInfo.environment["FASTLIST_BUILD_DOCS"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    )
}
