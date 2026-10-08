import Foundation

/// A player's snapshot plus the one thing about its cover that must stay on the device.
///
/// It is both what `RemoteMediaSnapshotMapper` reads from one report and what
/// `RemoteMediaSnapshotReducer` reconciles reports into; the reconciled state is the `previous` of the
/// next report. What is shown is derived from it by `displayedSnapshot(preparedArtworkFrom:)` and is a
/// plain `RemoteMediaSnapshot`, so it cannot be fed back in: a prepared cover belongs to one source and
/// is attached anew each time.
///
/// Deliberately not `Codable`. Only `snapshot` has a wire form.
public struct RemoteMediaEntityState: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let snapshot: RemoteMediaSnapshot
    /// Non-`nil` exactly when the track's cover is `deferred`: where to get it.
    let artworkReference: String?
    /// A digest of the server and entity the report came from.
    let artworkScope: RemoteMediaDigest
    /// Identifies `snapshot.track` for as long as the reducer treats later reports as the same track.
    /// `nil` exactly when there is no track.
    let trackIdentity: RemoteMediaDigest?

    init(
        snapshot: RemoteMediaSnapshot,
        artworkReference: String?,
        artworkScope: RemoteMediaDigest,
        trackIdentity: RemoteMediaDigest?
    ) {
        self.snapshot = snapshot
        self.artworkScope = artworkScope
        self.trackIdentity = snapshot.track == nil ? nil : trackIdentity
        self.artworkReference = snapshot.track?.artwork == .deferred ? artworkReference : nil
    }

    /// Where the cover of `snapshot.track` can be fetched, if it has one that is not prepared yet.
    public var artworkSource: RemoteMediaArtworkSource? {
        guard let artworkReference, let trackIdentity else { return nil }
        return RemoteMediaArtworkSource(artworkReference, scope: artworkScope, track: trackIdentity)
    }

    /// The snapshot to show, with the cover prepared from `source` attached.
    ///
    /// It is attached only when `source` is this state's own, so a cover prepared for an older source,
    /// another track or another player never shows, even at the same address. Whoever prepares covers
    /// compares `artworkSource` with what it last prepared, prepares again when they differ, stores the
    /// result under `source.cacheKey` (which already tells players, tracks and pictures apart) and passes
    /// it here; until then the track shows no cover rather than the old one.
    public func displayedSnapshot(preparedArtworkFrom source: RemoteMediaArtworkSource) -> RemoteMediaSnapshot {
        guard source == artworkSource, let track = snapshot.track else { return snapshot }
        return RemoteMediaSnapshot(
            player: snapshot.player,
            track: track.with(artwork: .available(.cached(source.cacheKey)))
        )
    }

    /// Leaves the artwork reference out, as `RemoteMediaArtworkSource` does: it is usually a token.
    public var description: String { "RemoteMediaEntityState(snapshot: \(snapshot))" }
    public var debugDescription: String { description }
}
