import Foundation
import ImageIO

/// A one-image cache per session, including in-flight requests. Commands never wait on this actor.
public actor RemoteMediaArtworkLoader {
    /// The system asks for artwork while it is already showing the card, so a download that never
    /// finishes has to fail rather than hold the request open.
    static let timeout: TimeInterval = 15
    /// Home Assistant proxies album art from the media player, which is a screen-sized image at
    /// worst. Anything larger is not artwork, and decoding it would cost the extension its memory.
    static let maximumBytes = 10 * 1024 * 1024

    private var key: String?
    private var download: Task<Data, Error>?

    public init() {}

    public func data(for snapshot: RemoteMediaSnapshot) async throws -> Data {
        RemoteMediaLog.logger.debug("artwork loader begin")
        guard let path = snapshot.artworkPath, !path.isEmpty else { throw RemoteMediaError.invalidArtwork }
        let requestedKey = snapshot.id + snapshot.trackId + path
        if key == requestedKey, let download { return try await download.value }
        download?.cancel()
        key = requestedKey
        let task = Task<Data, Error> {
            let server = Current.servers.server(forServerIdentifier: snapshot.selection.serverId)
            RemoteMediaLog.logger.debug("server resolved=\(server == nil ? "no" : "yes", privacy: .public)")
            guard let server else { throw RemoteMediaError.invalidArtwork }
            let activeURL = await server.activeURL()
            RemoteMediaLog.logger.debug("active host=\(activeURL?.host ?? "none", privacy: .public)")
            let api = Current.api(for: server)
            RemoteMediaLog.logger.debug("API resolved=\(api == nil ? "no" : "yes", privacy: .public)")
            guard let api,
                  let url = URL(string: path),
                  url.user == nil, url.password == nil else { throw RemoteMediaError.invalidArtwork }
            let resolved: URL
            let needsAuth: Bool
            if url.scheme == nil {
                RemoteMediaLog.logger.debug("artwork path kind=relative")
                // `entity_picture` is a server-relative path carrying a signed token in its query.
                // Resolve it against the server here: `DownloadDataAt` appends a relative URL as a
                // single path component, which percent-encodes the `?` and loses the token.
                guard path.hasPrefix("/"), !path.hasPrefix("//"),
                      let activeURL,
                      let absolute = URL(string: path, relativeTo: activeURL)?.absoluteURL else {
                    throw RemoteMediaError.invalidArtwork
                }
                resolved = absolute
                needsAuth = true
            } else {
                RemoteMediaLog.logger.debug("artwork path kind=absolute")
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    throw RemoteMediaError.invalidArtwork
                }
                resolved = url
                // Only the active HA origin may receive HA credentials.
                needsAuth = activeURL.map { url.baseIsEqual(to: $0) } ?? false
            }
            let resolutionDiagnostic = "artwork resolved scheme=\(resolved.scheme ?? "none") " +
                "host=\(resolved.host ?? "none") path=\(resolved.path) " +
                "query present=\(resolved.query == nil ? "no" : "yes") needsAuth=\(needsAuth ? "yes" : "no")"
            RemoteMediaLog.logger.debug("\(resolutionDiagnostic, privacy: .public)")
            RemoteMediaLog.logger.debug("download begin")
            let file = try await api.DownloadDataAt(url: resolved, needsAuth: needsAuth)
                .asyncValue(timeout: Self.timeout)
            defer { try? FileManager.default.removeItem(at: file) }
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= Self.maximumBytes else {
                throw RemoteMediaError.invalidArtwork
            }
            try Task.checkCancellation()
            let data = try Data(contentsOf: file)
            let source = CGImageSourceCreateWithData(data as CFData, nil)
            let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let width = properties?[kCGImagePropertyPixelWidth] as? Int
            let height = properties?[kCGImagePropertyPixelHeight] as? Int
            let type = source.flatMap { CGImageSourceGetType($0) as String? } ?? "unknown"
            let downloadDiagnostic = "download success bytes=\(data.count) type=\(type) " +
                "decodable=\(source == nil ? "no" : "yes") width=\(width ?? 0) height=\(height ?? 0)"
            RemoteMediaLog.logger.debug("\(downloadDiagnostic, privacy: .public)")
            return data
        }
        download = task
        do {
            return try await task.value
        } catch {
            if key == requestedKey { download = nil; key = nil }
            let diagnostic = "artwork loader failed type=\(String(reflecting: type(of: error))) " +
                "description=\(error.localizedDescription)"
            RemoteMediaLog.logger.error("\(diagnostic, privacy: .public)")
            throw error
        }
    }
}
