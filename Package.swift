// swift-tools-version: 5.9
import Foundation
import PackageDescription

let buildDocumentation = ProcessInfo.processInfo.environment["FASTLIST_BUILD_DOCS"] != nil

let package = Package(
    name: "FastList",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "FastList", targets: ["FastList"])
    ],
    dependencies: [
        .package(url: "https://github.com/adamtheturtle/MacPullToRefresh.git", from: "0.3.1")
    ],
    targets: [
        // SwiftPM's normal build treats the DocC catalog as an unhandled source. Exclude it
        // there, but expose it to the documentation plugin in the Pages build. Declaring it
        // as a documentation-build resource also keeps SwiftPM's source scan warning-free.
        .target(
            name: "FastList",
            exclude: buildDocumentation ? [] : ["FastList.docc"],
            resources: buildDocumentation ? [.copy("FastList.docc")] : []
        ),
        .executableTarget(
            name: "FastListDemo",
            dependencies: [
                "FastList",
                .product(name: "MacPullToRefresh", package: "MacPullToRefresh")
            ]
        ),
        .testTarget(name: "FastListTests", dependencies: ["FastList"])
    ]
)

// Pull in swift-docc-plugin only when building documentation (set in the Pages CI job),
// so it stays out of consumers' dependency graphs.
if buildDocumentation {
    package.dependencies.append(
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    )
}
