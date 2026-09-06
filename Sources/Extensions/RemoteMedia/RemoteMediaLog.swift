import OSLog

/// Logging for the RemoteMedia extension process.
///
/// This target deliberately does not use `Current.Log`. `Current` is a lazily initialised global
/// whose `Log` property reaches `AppConstants.LogsDirectory`, so touching it from the extension's
/// own start-up path re-enters that global's `dispatch_once` and traps the process. `OSLog` has no
/// such bootstrap requirement and is safe from the first line the extension runs.
enum RemoteMediaLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.home-assistant.RemoteMedia",
        category: "RemoteMedia"
    )
}
