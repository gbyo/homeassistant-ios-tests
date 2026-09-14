// swift-tools-version:5.9
import PackageDescription

// The Remote Now Playing wire model, reducer and mapper, kept in their own local package so every
// consumer compiles one module rather than its own copy of these sources. Foundation only: nothing
// here may reach for the app's networking, storage or session frameworks.
let package = Package(
    name: "RemoteMediaCore",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(name: "RemoteMediaCore", targets: ["RemoteMediaCore"]),
    ],
    targets: [
        .target(
            name: "RemoteMediaCore",
            path: "Sources"
        ),
    ]
)
