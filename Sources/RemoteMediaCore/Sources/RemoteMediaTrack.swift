import Foundation

/// The media a player is playing: what it is, how long it is, how far in, and its artwork.
///
/// A track only exists when something identifies it: at least one of `title`, `artist`, `album` or
/// `contentKey`. Duration, position and artwork describe a track that is already identified and are
/// not evidence of one by themselves — players report a duration, or a picture, while changing track
/// — so a report with only those has no track, exactly like a blank one. A snapshot represents that
/// as `track == nil` rather than as a track full of `nil`s.
///
/// Built only by `RemoteMediaSnapshotMapper`, by `RemoteMediaSnapshotReducer` and by decoding, and all
/// three go through the same normalization: empty strings are missing values, `duration` must be
/// positive, `position` is clamped to `0...duration`, a timestamp without a position is dropped,
/// and nothing non-finite survives.
public struct RemoteMediaTrack: Equatable, Sendable, Codable {
    public let title: String?
    public let artist: String?
    public let album: String?
    /// A digest of the entity's `media_content_id`. The id itself never leaves the server: it is
    /// whatever the integration chose, which can be a signed stream URL.
    public let contentKey: RemoteMediaDigest?
    /// Seconds. Always positive.
    public let duration: TimeInterval?
    /// Seconds into the track, as of `positionUpdatedAtUnix`. Never negative, never past `duration`.
    public let position: TimeInterval?
    /// When `position` was measured, in seconds since 1970-01-01 UTC — not `Date`'s 2001 reference
    /// epoch, so that a server never has to reproduce `JSONEncoder`'s date encoding.
    public let positionUpdatedAtUnix: TimeInterval?
    public let artwork: RemoteMediaArtwork

    init?(
        title: String?,
        artist: String?,
        album: String?,
        contentKey: RemoteMediaDigest?,
        duration: TimeInterval?,
        position: TimeInterval?,
        positionUpdatedAtUnix: TimeInterval?,
        artwork: RemoteMediaArtwork
    ) {
        let title = title.flatMap { $0.isEmpty ? nil : $0 }
        let artist = artist.flatMap { $0.isEmpty ? nil : $0 }
        let album = album.flatMap { $0.isEmpty ? nil : $0 }
        let duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard title != nil || artist != nil || album != nil || contentKey != nil else {
            return nil
        }
        let position = position.flatMap { $0.isFinite ? min(duration ?? .greatestFiniteMagnitude, max(0, $0)) : nil }
        self.title = title
        self.artist = artist
        self.album = album
        self.contentKey = contentKey
        self.duration = duration
        self.position = position
        self.positionUpdatedAtUnix = position == nil ? nil : positionUpdatedAtUnix.flatMap { $0.isFinite ? $0 : nil }
        self.artwork = artwork
    }

    private enum CodingKeys: String, CodingKey {
        case title, artist, album, contentKey, duration, position, positionUpdatedAtUnix, artwork
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let track = try Self(
            title: container.decodeIfPresent(String.self, forKey: .title),
            artist: container.decodeIfPresent(String.self, forKey: .artist),
            album: container.decodeIfPresent(String.self, forKey: .album),
            contentKey: container.decodeIfPresent(RemoteMediaDigest.self, forKey: .contentKey),
            duration: container.decodeIfPresent(TimeInterval.self, forKey: .duration),
            position: container.decodeIfPresent(TimeInterval.self, forKey: .position),
            positionUpdatedAtUnix: container.decodeIfPresent(TimeInterval.self, forKey: .positionUpdatedAtUnix),
            artwork: container.decode(RemoteMediaArtwork.self, forKey: .artwork)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "A track needs a title, artist, album or contentKey"
            ))
        }
        self = track
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(contentKey, forKey: .contentKey)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(positionUpdatedAtUnix, forKey: .positionUpdatedAtUnix)
        try container.encode(artwork, forKey: .artwork)
    }
}
