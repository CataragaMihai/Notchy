// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchyCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NotchyCore", targets: ["NotchyCore"]),
    ],
    targets: [
        .target(name: "NotchyCore"),
        .testTarget(name: "NotchyCoreTests", dependencies: ["NotchyCore"]),
    ]
)
