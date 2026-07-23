// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwitchboardIOS",
    platforms: [
        .iOS(.v17),
        // Host-side floor so `swift test` can build+run the Core unit tests on
        // macOS (Citadel/NIOSSH require macOS 14). The app itself ships iOS-only
        // via xcodegen+xcodebuild; this only affects host test builds.
        .macOS(.v14),
    ],
    products: [
        .library(name: "SwitchboardIOSCore", targets: ["SwitchboardIOSCore"]),
    ],
    dependencies: [
        // Citadel — modern pure-Swift SSH client. Powers the
        // `ssh mac.zerotier 'switchboard <cmd>'` transport.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.7.0"),
        // NIOTransportServices — Network.framework-backed transport.
        // Citadel's default ClientBootstrap uses NIOPosix's raw BSD
        // sockets, which on iOS DO NOT honor NetworkExtension VPN
        // routes (e.g. ZeroTier 172.23/16). NWConnection (used by
        // NIOTSConnectionBootstrap) routes via Network.framework which
        // does respect VPN tunnels — same path Safari/NSURLSession
        // takes. See v0.4 notes in SshClient.swift.
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
    ],
    targets: [
        .target(
            name: "SwitchboardIOSCore",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            path: "Sources/SwitchboardIOSCore"
        ),
        .testTarget(
            name: "SwitchboardIOSCoreTests",
            dependencies: ["SwitchboardIOSCore"],
            path: "Tests/SwitchboardIOSCoreTests"
        ),
    ]
)
