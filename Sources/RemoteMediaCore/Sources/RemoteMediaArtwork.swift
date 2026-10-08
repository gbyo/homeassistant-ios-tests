import Foundation

/// What is known about the cover of the track a snapshot shows: that no report offered one, that one
/// exists but is not prepared yet, or where the prepared copy is. Only `available` carries a
/// descriptor, so a descriptor and a status can never disagree.
public enum RemoteMediaArtwork: Equatable, Sendable {
    /// No picture was offered. This describes a report, not the track: Home Assistant leaves
    /// `entity_picture` out both when an entity has no picture and while an integration refreshes its
    /// attributes, and a report cannot say which. So `absent` is never a removal. A report that omits
    /// the picture keeps the one already known for the same track (`RemoteMediaSnapshotReducer`), and
    /// a cover ends with its track.
    case absent
    /// A cover exists but has not been prepared yet. `RemoteMediaEntityState.artworkSource` says
    /// where to get it.
    case deferred
    /// The cover has been prepared and stored. Never read from Home Assistant: it exists only in
    /// what `RemoteMediaEntityState.displayedSnapshot(preparedArtworkFrom:)` returns.
    case available(RemoteMediaArtworkDescriptor)
}
