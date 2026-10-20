// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IpBump",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ipbump-helper", targets: ["ipbump-helper"]),
    ],
    targets: [
        // Every rule IpBump follows, with no macOS API in it, so all of it runs under test with fakes
        .target(name: "IpBumpCore"),
        // The macOS side: SystemConfiguration, the helper's socket, the change lock
        .target(name: "IpBumpMac", dependencies: ["IpBumpCore"]),
        // BPF's ioctls are C macros Swift can't import
        .target(name: "CBPF"),
        // The root daemon: the only part that sends ARP probes or changes network settings
        .executableTarget(name: "ipbump-helper", dependencies: ["IpBumpCore", "IpBumpMac", "CBPF"]),
        .testTarget(name: "IpBumpCoreTests", dependencies: ["IpBumpCore"]),
        .testTarget(name: "IpBumpMacTests", dependencies: ["IpBumpMac", "IpBumpCore"]),
    ]
)
