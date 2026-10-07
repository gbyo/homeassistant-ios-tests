// swift-tools-version:5.9
import PackageDescription

// The Remote Now Playing model: what a followed `media_player` looks like on the wire, how one
// entity's attributes become that, and how successive reports are reconciled. Kept in its own local
// package so the app and the RemoteMedia extension share one module, and kept to system frameworks
// only so it never pulls the Companion dependency graph into the extension.
let package = Package(
    name: "RemoteMediaCore",
    platforms: [
        .iOS(.v16),
        // Not linked into any macOS target; declared so `swift test --package-path
        // Sources/RemoteMediaCore` works from the CLI, which builds for the host.
        .macOS(.v13),
    ],
    products: [
        .library(name: "RemoteMediaCore", targets: ["RemoteMediaCore"]),
    ],
    targets: [
        .target(
            name: "RemoteMediaCore",
            path: "Sources"
        ),
        .testTarget(
            name: "RemoteMediaCoreTests",
            dependencies: ["RemoteMediaCore"],
            path: "Tests"
        ),
    ]
)
