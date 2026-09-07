import Foundation

/// TEMPORARY shared probe log for the physical-device artwork investigation.
///
/// Host app and extension both append here, so one file shows the whole chain: what the host
/// received, what it wrote, and what the extension found. Lives in the App Group under `Library`
/// because that is the only place `devicectl` can copy from. Delete with the rest of the probe.
public enum RemoteMediaProbeLog {
    private static let lock = NSLock()

    public static func record(_ side: String, _ message: String) {
        RemoteMediaLog.logger.info("\(side, privacy: .public): \(message, privacy: .public)")
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL,
              let data = "\(Date().timeIntervalSince1970) [\(side)] pid=\(getpid()) \(message)\n".data(using: .utf8)
        else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static var fileURL: URL? {
        guard let container = RemoteMediaAppGroup.containerURL else { return nil }
        let directory = container.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("remote-media-probe-chain.log")
    }
}
