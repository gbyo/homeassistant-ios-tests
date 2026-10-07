import Foundation

/// Decides what to show for a followed player, given what was shown before and what Home Assistant
/// just reported.
///
/// "Follow in Now Playing" means follow this player until I stop following it — not "show a card only
/// while Home Assistant says `playing`". Integrations pass through transitional reports on the way to
/// a settled one: an Echo answering Pause can report `playing → idle → paused`, and can briefly clear
/// its media attributes entirely while changing track. Metadata often arrives in pieces, too.
///
/// So a snapshot is reconciled in its two halves, which change for different reasons:
///
/// - The **player** — name, playback state, volume, features — always comes from the newest report.
///   Keeping an old track on screen is no reason to keep old volume or old controls. The one
///   exception is an `indeterminate` playback state, which says the integration is not reporting,
///   not that playback stopped, so the previous playback state stands.
/// - The **track** is sticky. A report with no track keeps the previous one. A report describing the
///   same track fills in what it lacks from the previous one. A report describing a different track
///   replaces it outright, so nothing of the old track — least of all its artwork — leaks into the new.
///
/// This is a general resilience policy, deliberately not keyed on any integration's name. `previous`
/// must be this same player's last result: a snapshot carries nothing that says which player it
/// describes, so keeping one history per followed player is the caller's job.
public enum RemoteMediaSnapshotReducer {
    public static func reduce(previous: RemoteMediaSnapshot?, incoming: RemoteMediaSnapshot) -> RemoteMediaSnapshot {
        let player = incoming.player.playback == .indeterminate
            ? incoming.player.with(playback: previous?.player.playback ?? .indeterminate)
            : incoming.player

        let track: RemoteMediaTrack?
        switch (previous?.track, incoming.track) {
        case let (previous?, incoming?):
            track = isSameTrack(previous, incoming) ? merging(incoming, onto: previous) : incoming
        case let (previous, nil):
            track = previous
        case let (nil, incoming):
            track = incoming
        }
        return RemoteMediaSnapshot(player: player, track: track)
    }

    /// Whether two reports describe the same track.
    ///
    /// A missing value is incomplete information, not a different value, so only values present in
    /// both reports are compared:
    ///
    /// - Different `contentKey`s are different tracks.
    /// - A `title`, `artist` or `album` that differs is a different track even when the `contentKey`
    ///   matches, because radio streams and some integrations keep one content id across songs.
    /// - Otherwise, a shared `contentKey` is the same track. Without one, the reports must agree on at
    ///   least one of `title`, `artist` or `album`; with nothing in common, they are treated as
    ///   different, since carrying a previous track's metadata into an unrelated one is the worse
    ///   mistake.
    private static func isSameTrack(_ previous: RemoteMediaTrack, _ incoming: RemoteMediaTrack) -> Bool {
        let descriptive = [
            (previous.title, incoming.title),
            (previous.artist, incoming.artist),
            (previous.album, incoming.album),
        ]
        if let previousKey = previous.contentKey, let incomingKey = incoming.contentKey {
            if previousKey != incomingKey { return false }
        }
        for case let (previousValue?, incomingValue?) in descriptive where previousValue != incomingValue {
            return false
        }
        if previous.contentKey != nil, previous.contentKey == incoming.contentKey { return true }
        return descriptive.contains { previousValue, incomingValue in
            previousValue != nil && previousValue == incomingValue
        }
    }

    /// The same track, described by whichever of the two reports says more.
    ///
    /// Each value comes from `incoming` when it has one. Position and its timestamp move together, so
    /// a report without a position keeps the previous pair rather than mixing one with the other.
    /// Artwork follows the same rule, in order of how much it says: a descriptor from `incoming`, then
    /// one already known for this track, then `deferred` from either, then `absent`. So a cover is
    /// replaced by a newer cover, never by a report that merely lacks one.
    private static func merging(_ incoming: RemoteMediaTrack, onto previous: RemoteMediaTrack) -> RemoteMediaTrack {
        let measured = incoming.position == nil ? previous : incoming
        let artwork: RemoteMediaArtwork
        switch (incoming.artwork, previous.artwork) {
        case (.available, _), (.deferred, .absent), (.absent, .absent):
            artwork = incoming.artwork
        case (.deferred, _), (.absent, _):
            artwork = previous.artwork
        }
        // Both tracks already have something to identify them by, so neither can the merged one.
        return RemoteMediaTrack(
            title: incoming.title ?? previous.title,
            artist: incoming.artist ?? previous.artist,
            album: incoming.album ?? previous.album,
            contentKey: incoming.contentKey ?? previous.contentKey,
            duration: incoming.duration ?? previous.duration,
            position: measured.position,
            positionUpdatedAtUnix: measured.positionUpdatedAtUnix,
            artwork: artwork
        ) ?? incoming
    }
}
