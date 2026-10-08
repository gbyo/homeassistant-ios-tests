import Foundation

/// Where a track's prepared artwork is, in exactly one of the two forms it can take.
public enum RemoteMediaArtworkDescriptor: Equatable, Sendable {
    /// An image the host app has already fetched and stored in the cache the app and the extension
    /// share, named by this digest. Only the device itself can produce one of these.
    case cached(RemoteMediaDigest)
    /// An image anyone can fetch with no credentials, published by a server. See
    /// `RemoteMediaArtworkURL`.
    case remote(RemoteMediaArtworkURL)
}
