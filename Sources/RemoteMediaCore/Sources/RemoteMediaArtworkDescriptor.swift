import Foundation

/// Where this track's artwork can be found, and how to name it in the cache.
///
/// Whoever builds one of these knows only one of the two forms: a caller that has already fetched
/// and downsampled the image supplies `cacheKey`, and a caller that can only say where the image
/// lives supplies `url`.
///
/// **Caller requirement, not an invariant this type enforces:** `url` must be a credential-free
/// absolute HTTPS URL. A `media_player`'s `entity_picture` is often a Home Assistant proxy path
/// carrying a signed token, and a descriptor is carried inside `RemoteMediaSnapshot`, whose JSON
/// leaves the app's control — so that form must never be put here. Where artwork exists only behind
/// Home Assistant's own authentication, the right descriptor has no `url` at all.
public struct RemoteMediaArtworkDescriptor: Codable, Equatable, Sendable {
    /// The cache file, when whoever built this had already written it.
    public let cacheKey: String?
    /// A source that can be fetched with no credentials of any kind.
    public let url: URL?

    public init(cacheKey: String? = nil, url: URL? = nil) {
        self.cacheKey = cacheKey
        self.url = url
    }

    /// What a one-image-per-content-identity cache keys on.
    ///
    /// A track change has to change this or the previous song's cover stays on screen, and it must
    /// not contain a token, because a consumer is free to log or persist it.
    public var identity: String {
        cacheKey ?? url?.absoluteString ?? ""
    }
}
