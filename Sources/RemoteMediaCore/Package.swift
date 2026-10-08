// swift-tools-version:5.9
import PackageDescription

// The Remote Now Playing model: how one `media_player` entity's attributes become what Now Playing
// shows, and how successive reports are reconciled. Kept in its own local package, and to system
// frameworks only, so the app and the RemoteMedia extension can share it later without pulling the
// Companion dependency graph into the extension.
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
