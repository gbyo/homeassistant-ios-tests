import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
        // descriptor — or one that only ever carried a source — cannot reach outside the cache
        // directory.
        guard let key = descriptor.cacheKey else { return nil }
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

    /// Decodes the cached image at the size the system actually asked for.
    ///
    /// Decoding the file at its full size cost the extension around a megabyte of its 6144 KB
    /// ledger, and the peak measured on device sat at 91% of the limit. `Artwork`'s provider is
    /// handed the size it wants, so ImageIO produces a thumbnail at that size instead and the
    /// footprint scales with what is rendered rather than with what was stored.
    ///
    /// Never upscales: a request larger than the stored image decodes it as it is.
    static func thumbnailImage(from data: Data, requestedSize: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            RemoteMediaLog.logger.error(
                "artwork decode result=not an image bytes=\(data.count, privacy: .public)"
            )
            return nil
        }
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
        // What ImageIO thinks it was handed, before it is asked for anything: a decode that fails
        // and a source that was never an image look identical from the outside.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let sourceWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let sourceHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        // The collapsed Lock Screen thumbnail and the expanded presentation are two requests for
        // the same track, and only the second one renders gray. Whether that is because it asked
        // for more than the host app stored is not knowable from this side without the numbers, so
        // all four are recorded together: what was asked for, what is on disk, what was served, and
        // whether it was clamped.
        RemoteMediaLog.logger.info(
            """
            artwork decode requested=\(maximumPixelSize, privacy: .public) \
            source=\(sourceWidth, privacy: .public)x\(sourceHeight, privacy: .public) \
            stored=\(storedPixelSize, privacy: .public) \
            bytes=\(data.count, privacy: .public) \
            served=\(image?.width ?? 0, privacy: .public)x\(image?.height ?? 0, privacy: .public) \
            clamped=\(maximumPixelSize > storedPixelSize, privacy: .public) \
            result=\(image == nil ? "failed" : "ok", privacy: .public)
            """
        )
        return image
    }

    /// The same thumbnail, encoded, which is the only form that survives the trip to the system.
    ///
    /// The artwork callback's reply is serialized over NSXPC, and a `CGImage` in the returned
    /// object graph makes `NSXPCEncoder` throw — deterministically, on the device, once the
    /// provider finally started returning pixels at all. So the decoded image never leaves this
    /// function: it is downsampled, re-encoded, and only the bytes are handed back.
    ///
    /// Re-encoding is not wasted work. The decode has to happen to resize at all, and the peak is
    /// the same as it ever was — one thumbnail-sized image, which is why the size the system asked
    /// for is what it is decoded at rather than the size on disk.
    static func thumbnailData(from data: Data, requestedSize: CGSize) -> Data? {
        guard let image = thumbnailImage(from: data, requestedSize: requestedSize) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            RemoteMediaLog.logger.error("artwork encode result=no destination")
            return nil
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: encodeQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            RemoteMediaLog.logger.error("artwork encode result=failed")
            return nil
        }
        return output as Data
    }

    /// High enough that a re-encode of an already-compressed cover is not visibly worse.
    static let encodeQuality = 0.9

    /// The largest dimension the host app stores, which is also the ceiling for a decode: asking
    /// ImageIO for more than this would only upscale.
    static let storedPixelSize = 512

    public static func store(_ data: Data, for descriptor: RemoteMediaArtworkDescriptor) throws {
        guard let directory = directoryURL, let url = url(for: descriptor) else {
            RemoteMediaLog.logger.error("artwork store result=no cache location")
            return
        }
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
