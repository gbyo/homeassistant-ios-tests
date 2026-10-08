import Foundation

/// One followed `media_player` as Remote Now Playing shows it.
///
/// A snapshot is published outside the app, so its values are constrained by type rather than by
/// convention: display strings the entity already publishes, `RemoteMediaDigest`s instead of raw
/// integration values, and a `RemoteMediaArtwork`.
///
/// There is no field for routing or authentication: no server id, entity id, webhook, URL, credential
/// or transport state. Whatever follows the player keeps those locally. An entity id can appear only
/// as `player.name`, the display fallback when the entity has no `friendly_name`, which is what Home
/// Assistant itself shows.
public struct RemoteMediaSnapshot: Equatable, Sendable {
    public let player: RemoteMediaPlayer
    /// What is playing, or `nil` when the player reports nothing to show.
    public let track: RemoteMediaTrack?

    init(player: RemoteMediaPlayer, track: RemoteMediaTrack?) {
        self.player = player
        self.track = track
    }
}
