import Foundation

/// Where a track's cover can be fetched: the entity's `entity_picture`, verbatim.
///
/// For the app to fetch through its own authenticated connection. It is usually a Home Assistant proxy
/// path whose query is an access token, so callers must treat `reference` as a credential. This type
/// keeps it out of snapshots, and `description` and `debugDescription` do not expose it. It makes no
/// other guarantee: callers must not log or persist `reference`.
///
/// A source is also bound to the player (server and entity) and the track it was reported for, because
/// `entity_picture` is usually a path relative to its server and one address can serve different
/// images. Two sources are equal only when all three are, which is how a changed cover is noticed: what
/// was prepared from an old source stops applying (`RemoteMediaEntityState.displayedSnapshot`).
/// Equality can be stricter than the picture: if Home Assistant re-issues its proxy token, the same
/// picture is fetched once more.
public struct RemoteMediaArtworkSource: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// `entity_picture` exactly as the entity reported it: a server-relative path or an absolute URL.
    /// Treat it as a credential.
    public let reference: String
    /// A digest of the server and entity it was reported by, which are local routing.
    private let scope: RemoteMediaDigest
    /// The track it was reported for, as `RemoteMediaTrack.identity` defines it.
    private let track: RemoteMediaDigest

    init(_ reference: String, scope: RemoteMediaDigest, track: RemoteMediaDigest) {
        self.reference = reference
        self.scope = scope
        self.track = track
    }

    /// Names this source's prepared copy in the cache the app and the extension share. A digest, so a
    /// snapshot carrying it reveals nothing about the source, server or entity. It covers the player and
    /// track as well as the picture, since the extension takes a changed key to mean a changed cover; it
    /// is stable within a track and across relaunches, so metadata filling in later costs no new fetch.
    public var cacheKey: RemoteMediaDigest {
        RemoteMediaDigest(hashingFields: [scope.hexString, track.hexString, reference])
    }

    public var description: String { "RemoteMediaArtworkSource" }
    public var debugDescription: String { description }
}
