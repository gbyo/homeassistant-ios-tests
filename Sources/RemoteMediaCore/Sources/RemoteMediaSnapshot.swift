import Foundation

/// One followed `media_player` as Remote Now Playing shows it: the wire contract.
///
/// This is encoded as JSON that leaves the app through Apple's Remote Media infrastructure, and a
/// Home Assistant server has to be able to produce exactly the same JSON. So the shape is closed and
/// every value in it is constrained by its type rather than by convention:
///
/// - the player name and track metadata are display strings the entity already publishes;
/// - identifiers are `RemoteMediaDigest`s, never raw integration values;
/// - artwork is a `RemoteMediaArtwork`, whose only URL form is a `RemoteMediaArtworkURL`;
/// - timestamps are Unix seconds.
///
/// There is no field for routing or authentication: no server id, entity id, webhook id or URL,
/// credential, push token or transport state. Whatever follows the player keeps those locally. The
/// one place an entity id can appear is `player.name`, as the display fallback when the entity has
/// no `friendly_name` — which is what Home Assistant itself shows in that case, and not a secret.
public struct RemoteMediaSnapshot: Equatable, Sendable, Codable {
    public let player: RemoteMediaPlayer
    /// What is playing, or `nil` when the player reports nothing to show.
    public let track: RemoteMediaTrack?

    init(player: RemoteMediaPlayer, track: RemoteMediaTrack?) {
        self.player = player
        self.track = track
    }
}
