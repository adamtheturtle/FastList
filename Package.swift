// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastList",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FastList", targets: ["FastList"])
    ],
    targets: [
        .target(name: "FastList"),
        .testTarget(name: "FastListTests", dependencies: ["FastList"])
    ]
)
