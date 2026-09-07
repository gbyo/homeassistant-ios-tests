import Darwin
import Foundation
import MachO
import os
import OSLog

/// Temporary physical-device instrumentation for the extension jetsam investigation.
///
/// Reports the process footprint jetsam actually measures (`phys_footprint`) plus the loaded
/// image graph, so the full-`Shared` and no-`Shared` builds can be compared with numbers rather
/// than only survival. Remove together with the rest of the probe code.
enum RemoteMediaFootprint {
    /// Resident footprint in bytes, as `per-process-limit` jetsam accounts for it.
    static func physFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), pointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    /// Non-system images, which is where the Companion dependency graph shows up.
    static func projectImages() -> [String] {
        (0 ..< _dyld_image_count()).compactMap { index in
            guard let name = _dyld_get_image_name(index) else { return nil }
            let path = String(cString: name)
            guard !path.hasPrefix("/System/"), !path.hasPrefix("/usr/lib/") else { return nil }
            return (path as NSString).lastPathComponent
        }
    }

    /// Bytes left before this process hits its jetsam limit, per the public extension-safe API.
    ///
    /// Added to `physFootprint()` this yields the limit itself, which is the number the whole
    /// investigation turns on: the device's jetsam report shows the kill happening at ~6 MB
    /// resident, far below anything a dependency graph alone explains.
    static func availableMemory() -> Int { os_proc_available_memory() }

    static func log(_ stage: String) {
        let footprint = physFootprint()
        let available = availableMemory()
        let limit = footprint.map { Int($0) + available }
        let message = "footprint stage=\(stage) " +
            "phys_footprint=\(footprint.map { String($0 / 1024) } ?? "?") KB " +
            "available=\(available / 1024) KB " +
            "limit=\(limit.map { String($0 / 1024) } ?? "?") KB " +
            "images total=\(_dyld_image_count()) project=\(projectImages().count) " +
            "[\(projectImages().joined(separator: ","))]"
        RemoteMediaLog.logger.info("\(message, privacy: .public)")
        append(message)
    }

    // MARK: - App group readback

    /// Mirrors each line into the App Group so `devicectl` can pull it without Console.app.
    ///
    /// Only `Library`, `Documents` and `tmp` are transferable, so this deliberately does not sit
    /// beside the existing container-root probe log. Derived from the bundle id rather than
    /// `AppConstants` so the no-`Shared` variant can use the same file.
    private static let fileLock = NSLock()

    private static var logURL: URL? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let hostID = bundleID.hasSuffix(".RemoteMedia") ? String(bundleID.dropLast(".RemoteMedia".count)) : bundleID
        let group = "group." + hostID.replacingOccurrences(of: ".HomeAssistant", with: ".homeassistant")
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let directory = container.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("remote-media-footprint.log")
    }

    private static func append(_ message: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let url = logURL,
              let data = "\(Date().timeIntervalSince1970) pid=\(getpid()) \(message)\n".data(using: .utf8)
        else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
