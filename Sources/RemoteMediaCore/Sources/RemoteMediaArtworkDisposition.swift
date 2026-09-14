import Foundation

/// What a snapshot's missing `artwork` means.
///
/// Without this, "no descriptor" would have to stand for two opposite situations, and
/// `RemoteMediaSnapshotReducer` would have no way to tell them apart.
public enum RemoteMediaArtworkDisposition: String, Codable, Equatable, Sendable {
    /// A cover exists but has not been prepared yet, so whatever is already shown for this track
    /// should stay.
    case deferred
    /// The snapshot carries the descriptor to use.
    case available
    /// There is no cover for this track; anything still shown should be cleared.
    case absent
}
