import Foundation
import OSLog

/// Extension-safe logging for Remote Now Playing.
///
/// This deliberately does not use `Current.Log`: touching that dependency from the RemoteMedia
/// extension can re-enter global environment initialization while the extension is launching.
public enum RemoteMediaLog {
    public static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.home-assistant.RemoteMedia",
        category: "RemoteMedia"
    )

    #if DEBUG
    /// Takes a footprint reading, when something has installed a way to.
    ///
    /// The extension is the only process with a 6144 KB ledger to answer to, and its measurement
    /// lives there — but the work worth measuring happens in code the extension shares with the
    /// app, which cannot reach it. The extension installs this on launch; everywhere else it stays
    /// `nil` and costs a branch.
    public nonisolated(unsafe) static var footprint: (@Sendable (String) -> Void)?
    #endif
}
