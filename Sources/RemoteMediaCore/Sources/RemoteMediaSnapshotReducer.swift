import Foundation

/// Decides what to show for a followed player, given what was shown before and what Home Assistant
/// just reported.
///
/// "Follow in Now Playing" means follow this player until I stop following it, not "show a card only
/// while Home Assistant says `playing`". Integrations pass through transitional reports (an Echo
/// answering Pause can report `playing → idle → paused`, or briefly clear its media attributes while
/// changing track) and send metadata in pieces. So the two halves are reconciled differently:
///
/// - The **player** always comes from the newest report. The exception is `indeterminate`, which says
///   the integration is not reporting rather than that playback stopped, so the previous playback
///   state stands.
/// - The **track** is sticky. A report with no track keeps the previous one; one describing the same
///   track fills in what it lacks; one describing a different track replaces it outright, so nothing
///   of the old track leaks into the new. The cover is part of the track: a report that leaves the
///   picture out keeps the known one (Home Assistant cannot tell an omitted picture from a withdrawn
///   one, see `RemoteMediaArtwork`), and one that offers a picture replaces it. A track keeps the
///   identity it was first reported with, which binds its cover's source to it.
///
/// `previous` must be this same player's last reconciled state, not what was displayed from it.
public enum RemoteMediaSnapshotReducer {
    public static func reduce(
        previous: RemoteMediaEntityState?,
        incoming: RemoteMediaEntityState
    ) -> RemoteMediaEntityState {
        let player = incoming.snapshot.player.playback == .indeterminate
            ? incoming.snapshot.player.with(playback: previous?.snapshot.player.playback ?? .indeterminate)
            : incoming.snapshot.player

        // A cover's reference and the identity that ties it to its track follow the track.
        let track: RemoteMediaTrack?
        let trackIdentity: RemoteMediaDigest?
        let artworkReference: String?
        switch (previous?.snapshot.track, incoming.snapshot.track) {
        case let (previousTrack?, incomingTrack?) where isSameTrack(previousTrack, incomingTrack):
            track = merging(incomingTrack, onto: previousTrack)
            trackIdentity = previous?.trackIdentity ?? incomingTrack.identity
            artworkReference = incoming.artworkReference ?? previous?.artworkReference
        case let (_, incomingTrack?):
            track = incomingTrack
            trackIdentity = incoming.trackIdentity
            artworkReference = incoming.artworkReference
        case let (previousTrack, nil):
            track = previousTrack
            trackIdentity = previous?.trackIdentity
            artworkReference = previous?.artworkReference
        }
        return RemoteMediaEntityState(
            snapshot: RemoteMediaSnapshot(player: player, track: track),
            artworkReference: artworkReference,
            artworkScope: incoming.artworkScope,
            trackIdentity: trackIdentity
        )
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
    /// The cover is the same: `incoming`'s when it offers one, otherwise the one already known.
    private static func merging(_ incoming: RemoteMediaTrack, onto previous: RemoteMediaTrack) -> RemoteMediaTrack {
        let measured = incoming.position == nil ? previous : incoming
        // Both tracks already have something to identify them by, so neither can the merged one.
        return RemoteMediaTrack(
            title: incoming.title ?? previous.title,
            artist: incoming.artist ?? previous.artist,
            album: incoming.album ?? previous.album,
            contentKey: incoming.contentKey ?? previous.contentKey,
            duration: incoming.duration ?? previous.duration,
            position: measured.position,
            positionUpdatedAtUnix: measured.positionUpdatedAtUnix,
            artwork: incoming.artwork == .absent ? previous.artwork : incoming.artwork
        ) ?? incoming
    }
}
