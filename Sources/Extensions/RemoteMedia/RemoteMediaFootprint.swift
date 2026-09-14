#if DEBUG
import Darwin
import Foundation
import os
import OSLog

/// Reports the extension's footprint against the ledger jetsam actually enforces.
///
/// This process is killed at 6144 KB, which is small enough that a change's memory cost has to be
/// measured rather than reasoned about. Deliberately minimal: it reads two counters and writes one
/// line, because instrumentation that allocates distorts the number it is reporting.
enum RemoteMediaFootprint {
    static func log(_ stage: String) {
        guard let footprint = physFootprint() else { return }
        let available = os_proc_available_memory()
        RemoteMediaLog.logger.debug(
            """
            footprint stage=\(stage, privacy: .public) \
            phys_footprint=\(footprint / 1024, privacy: .public) KB \
            available=\(available / 1024, privacy: .public) KB
            """
        )
        append("\(stage) \(footprint / 1024) \(available / 1024)")
    }

    /// Resident footprint in bytes, as `per-process-limit` jetsam accounts for it.
    private static func physFootprint() -> UInt64? {
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

    /// Mirrored into the App Group so a reading can be collected from a device without attaching
    /// a console. The URL is resolved once: the container lookup is a syscall.
    private static let lock = NSLock()
    private static let fileURL: URL? = {
        guard let container = RemoteMediaAppGroup.containerURL else { return nil }
        let directory = container.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("remote-media-footprint.log")
    }()

    private static func append(_ line: String) {
        guard let fileURL else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let data = "\(getpid()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
#endif
