// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IpBump",
    platforms: [.macOS(.v14)],
    targets: [
        // Every rule IpBump follows, with no macOS API in it, so all of it runs under test with fakes
        .target(name: "IpBumpCore"),
        // The macOS side: SystemConfiguration, the helper's socket, the change lock
        .target(name: "IpBumpMac", dependencies: ["IpBumpCore"]),
        .testTarget(name: "IpBumpCoreTests", dependencies: ["IpBumpCore"]),
        .testTarget(name: "IpBumpMacTests", dependencies: ["IpBumpMac", "IpBumpCore"]),
    ]
)
