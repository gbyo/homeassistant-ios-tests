import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fetches and downsamples album art in the host app, then leaves it in the App Group for the
/// extension to read.
///
/// All of this used to happen inside the extension, where a full-size decode took it from 3.7 MB to
/// 5.4 MB of a 6144 KB ledger. Here there is no such budget, and the extension is left with nothing
/// to do but read a small JPEG off disk.
public actor RemoteMediaArtworkPreparer {
    /// Now Playing renders artwork at screen size at most; anything larger is wasted bytes in the
    /// group container and wasted decode in the extension.
    static let maximumPixelSize = 512
    static let compressionQuality = 0.8
    static let timeout: TimeInterval = 15
    /// Home Assistant proxies album art from the player, which is screen-sized at worst.
    static let maximumSourceBytes = 10 * 1024 * 1024

    private var inFlight: [String: Task<RemoteMediaArtworkDescriptor?, Never>] = [:]

    public init() {}

    /// The descriptor for this state's artwork, preparing it first if it is not cached yet.
    /// Returns `nil` whenever artwork cannot be produced — it is optional and never fails a session.
    public func descriptor(for state: RemoteMediaEntityState) async -> RemoteMediaArtworkDescriptor? {
        guard let source = state.artworkSource, !source.isEmpty else { return nil }
        let snapshot = state.snapshot
        let key = RemoteMediaArtworkCache.key(
            sessionId: snapshot.id,
            trackId: snapshot.trackId,
            source: source
        )
        let descriptor = RemoteMediaArtworkDescriptor(cacheKey: key)
        RemoteMediaProbeLog.record("host", "artwork requested key=\(key) source=\"\(source.prefix(60))\"")
        if let cached = RemoteMediaArtworkCache.data(for: descriptor) {
            RemoteMediaProbeLog.record("host", "artwork cache hit bytes=\(cached.count)")
            return descriptor
        }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<RemoteMediaArtworkDescriptor?, Never> { [serverId = snapshot.selection.serverId] in
            do {
                let data = try await Self.download(source: source, serverId: serverId)
                RemoteMediaProbeLog.record("host", "artwork downloaded bytes=\(data.count)")
                guard let prepared = Self.downsample(data) else {
                    RemoteMediaProbeLog.record("host", "artwork downsample FAILED")
                    throw RemoteMediaError.invalidArtwork
                }
                try RemoteMediaArtworkCache.store(prepared, for: descriptor)
                let url = RemoteMediaArtworkCache.url(for: descriptor)
                let onDisk = url.flatMap { try? FileManager.default
                    .attributesOfItem(atPath: $0.path)[.size] as? Int } ?? nil
                RemoteMediaProbeLog.record("host", "artwork stored bytes=\(prepared.count) " +
                    "onDisk=\(onDisk.map(String.init) ?? "MISSING") path=\(url?.path ?? "nil")")
                return descriptor
            } catch {
                RemoteMediaProbeLog.record("host", "artwork preparation FAILED " +
                    "type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private static func download(source: String, serverId: String) async throws -> Data {
        let server = Current.servers.server(forServerIdentifier: serverId)
        let api = server.flatMap { Current.api(for: $0) }
        guard let server, let api,
              let url = URL(string: source), url.user == nil, url.password == nil else {
            RemoteMediaProbeLog.record("host", "artwork download setup FAILED " +
                "server=\(server != nil) api=\(api != nil) parsable=\(URL(string: source) != nil)")
            throw RemoteMediaError.invalidArtwork
        }
        let activeURL = await server.activeURL()
        let resolved: URL
        let needsAuth: Bool
        if url.scheme == nil {
            // `entity_picture` is a server-relative path carrying a signed token in its query.
            // Resolve it here: appending it as a path component percent-encodes the `?` and loses
            // the token.
            guard source.hasPrefix("/"), !source.hasPrefix("//"),
                  let activeURL,
                  let absolute = URL(string: source, relativeTo: activeURL)?.absoluteURL else {
                throw RemoteMediaError.invalidArtwork
            }
            resolved = absolute
            needsAuth = true
        } else {
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw RemoteMediaError.invalidArtwork
            }
            resolved = url
            // Only the active Home Assistant origin may receive Home Assistant credentials.
            needsAuth = activeURL.map { url.baseIsEqual(to: $0) } ?? false
        }

        RemoteMediaProbeLog.record("host", "artwork download begin host=\(resolved.host ?? "none") " +
            "path=\(resolved.path) needsAuth=\(needsAuth)")
        let file = try await api.DownloadDataAt(url: resolved, needsAuth: needsAuth)
            .asyncValue(timeout: timeout)
        defer { try? FileManager.default.removeItem(at: file) }
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= maximumSourceBytes else {
            throw RemoteMediaError.invalidArtwork
        }
        return try Data(contentsOf: file)
    }

    /// Downsamples with ImageIO rather than decoding at full resolution, and never upscales.
    static func downsample(_ data: Data, maximumPixelSize: Int = maximumPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
