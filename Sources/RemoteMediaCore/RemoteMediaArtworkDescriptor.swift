import Foundation

/// Points the extension at artwork the host app has already fetched, downsampled and cached.
///
/// Only a cache key crosses the RemoteMedia boundary. The source `entity_picture` path carries a
/// signed token, and these attributes are serialized through Apple's infrastructure, so the source
/// URL deliberately stays in the host app.
public struct RemoteMediaArtworkDescriptor: Codable, Equatable, Sendable {
    /// Identifies both the cache file and the artwork's identity, so a new track never shows the
    /// previous track's image.
    public let cacheKey: String

    public init(cacheKey: String) { self.cacheKey = cacheKey }
}
