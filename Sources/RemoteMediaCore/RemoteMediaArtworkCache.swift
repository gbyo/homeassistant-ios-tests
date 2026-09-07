import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// The App Group directory the host app writes prepared artwork into and the extension reads from.
///
/// The extension never fetches or downsamples an image: at 6144 KB it cannot afford to, and a real
/// artwork decode is what pushed the previous implementation into `per-process-limit`. Reading a
/// small pre-sized JPEG off disk costs it almost nothing.
public enum RemoteMediaArtworkCache {
    /// How many prepared images to keep. Enough for the current track plus recent history, so
    /// skipping back and forth does not refetch, and bounded so the group container cannot grow.
    static let maximumEntries = 8

    public static var directoryURL: URL? {
        RemoteMediaAppGroup.containerURL?
            .appendingPathComponent("Library/Caches/RemoteMediaArtwork", isDirectory: true)
    }

    /// A stable name for one track's artwork. Changing track or artwork source changes the key, so
    /// the extension can never be handed the previous track's image.
    public static func key(sessionId: String, trackId: String, source: String) -> String {
        let identity = "\(sessionId.utf8.count):\(sessionId)\(trackId.utf8.count):\(trackId)\(source)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func url(for descriptor: RemoteMediaArtworkDescriptor) -> URL? {
        // Guard against a key that is not the hex digest this cache writes, so a malformed
        // descriptor cannot reach outside the cache directory.
        let key = descriptor.cacheKey
        guard key.count == 64, key.allSatisfy(\.isHexDigit) else { return nil }
        return directoryURL?.appendingPathComponent(key, isDirectory: false)
    }

    /// The cached bytes, or `nil` when nothing usable is there. Missing and unreadable are the same
    /// answer on purpose: artwork is optional and must never fail a session.
    public static func data(for descriptor: RemoteMediaArtworkDescriptor) -> Data? {
        guard let url = url(for: descriptor) else { return nil }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    /// Whether prepared artwork is already on disk, without reading it. The host checks this on the
    /// main actor before publishing, so it must not pull the image into memory.
    public static func contains(_ descriptor: RemoteMediaArtworkDescriptor) -> Bool {
        guard let url = url(for: descriptor) else { return false }
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        return (size ?? 0) > 0
    }

    /// How long the extension will wait for the host app to finish preparing an image.
    ///
    /// The session is published with its artwork key as soon as the key is known, before the file
    /// exists: the system asks for an image once per content identity, so a card published without
    /// artwork and corrected later just stays blank. `Artwork`'s provider is `async`, so the
    /// honest thing is to make the system wait the short time preparation takes.
    static let waitForPreparation: TimeInterval = 8
    private static let pollInterval: Duration = .milliseconds(100)

    /// The cached bytes, waiting up to `waitForPreparation` for the host app to write them.
    ///
    /// Costs the extension nothing but time — no network, no decode — which is the whole point of
    /// preparing artwork in the host process.
    public static func data(
        for descriptor: RemoteMediaArtworkDescriptor,
        waitingForPreparation: Bool
    ) async -> Data? {
        if let data = data(for: descriptor) { return data }
        guard waitingForPreparation else { return nil }

        let deadline = Date().addingTimeInterval(waitForPreparation)
        while Date() < deadline {
            try? await Task.sleep(for: pollInterval)
            if Task.isCancelled { return nil }
            if let data = data(for: descriptor) { return data }
        }
        return nil
    }

    /// Decodes the cached image at the size the system actually asked for.
    ///
    /// Decoding the file at its full size cost the extension around a megabyte of its 6144 KB
    /// ledger, and the peak measured on device sat at 91% of the limit. `Artwork`'s provider is
    /// handed the size it wants, so ImageIO produces a thumbnail at that size instead and the
    /// footprint scales with what is rendered rather than with what was stored.
    ///
    /// Never upscales: a request larger than the stored image decodes it as it is.
    public static func thumbnail(from data: Data, requestedSize: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let requested = max(requestedSize.width, requestedSize.height)
        let maximumPixelSize = requested.isFinite && requested >= 1 ? Int(requested.rounded(.up)) : storedPixelSize
        let served = min(maximumPixelSize, storedPixelSize)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // ImageIO holding its own copy of the decode is exactly what there is no room for.
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: served,
        ]
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        // The collapsed Lock Screen thumbnail and the expanded presentation are two requests for
        // the same track, and only the second one renders gray. Whether that is because it asked
        // for more than the host app stored is not knowable from this side without the numbers, so
        // all four are recorded together: what was asked for, what is on disk, what was served, and
        // whether it was clamped.
        RemoteMediaLog.logger.info(
            """
            artwork requested=\(maximumPixelSize, privacy: .public) \
            stored=\(storedPixelSize, privacy: .public) \
            bytes=\(data.count, privacy: .public) \
            served=\(image?.width ?? 0, privacy: .public)x\(image?.height ?? 0, privacy: .public) \
            clamped=\(maximumPixelSize > storedPixelSize, privacy: .public)
            """
        )
        return image
    }

    /// The largest dimension the host app stores, which is also the ceiling for a decode: asking
    /// ImageIO for more than this would only upscale.
    static let storedPixelSize = 512

    public static func store(_ data: Data, for descriptor: RemoteMediaArtworkDescriptor) throws {
        guard let directory = directoryURL, let url = url(for: descriptor) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        prune(in: directory, keeping: url)
    }

    /// Drops the least recently modified entries beyond `maximumEntries`.
    ///
    /// `keeping` is never evicted. Modification dates have coarse resolution, so several images
    /// written in the same instant — a user skipping tracks quickly — sort arbitrarily, and without
    /// this the image just written could be the one thrown away, leaving the current track blank.
    static func prune(in directory: URL, keeping: URL? = nil) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ), entries.count > maximumEntries else { return }

        let sorted = entries.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            return leftDate > rightDate
        }
        let keepPath = keeping?.standardizedFileURL.path
        var budget = maximumEntries
        if let keepPath, sorted.contains(where: { $0.standardizedFileURL.path == keepPath }) {
            budget -= 1
        }
        var kept = 0
        for url in sorted where url.standardizedFileURL.path != keepPath {
            guard kept >= budget else {
                kept += 1
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func removeAll() {
        guard let directory = directoryURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
