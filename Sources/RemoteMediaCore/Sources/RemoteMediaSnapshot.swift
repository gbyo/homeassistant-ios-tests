import Foundation

/// One followed `media_player` as Remote Now Playing shows it: the wire contract.
///
/// This is encoded as JSON that leaves the app through Apple's Remote Media infrastructure, and a Home
/// Assistant server has to produce exactly the same JSON. So the shape is closed and its values are
/// constrained by type rather than by convention: display strings the entity already publishes,
/// `RemoteMediaDigest`s instead of raw integration values, a `RemoteMediaArtwork` whose only URL form
/// is a `RemoteMediaArtworkURL`, and timestamps in Unix seconds.
///
/// There is no field for routing or authentication: no server id, entity id, webhook, URL, credential
/// or transport state. Whatever follows the player keeps those locally. An entity id can appear only
/// as `player.name`, the display fallback when the entity has no `friendly_name`, which is what Home
/// Assistant itself shows.
public struct RemoteMediaSnapshot: Equatable, Sendable, Codable {
    public let player: RemoteMediaPlayer
    /// What is playing, or `nil` when the player reports nothing to show.
    public let track: RemoteMediaTrack?

    init(player: RemoteMediaPlayer, track: RemoteMediaTrack?) {
        self.player = player
        self.track = track
    }
}
