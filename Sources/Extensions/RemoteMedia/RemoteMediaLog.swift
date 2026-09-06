import Foundation
import OSLog

/// Logging for the RemoteMedia extension's earliest startup boundary.
///
/// Shared RemoteMedia code has an equivalent logger because neither path may touch `Current.Log`
/// while running inside the extension process.
enum RemoteMediaLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.home-assistant.RemoteMedia",
        category: "RemoteMedia"
    )
}
