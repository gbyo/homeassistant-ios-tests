import Foundation

/// What `RemoteMediaSnapshotMapper` reads from one entity: the wire-safe snapshot, and the values
/// that are useful on the device but must not travel with it.
///
/// Deliberately not `Codable`. Only `snapshot` has a wire form.
public struct RemoteMediaEntityState: Equatable, Sendable {
    public let snapshot: RemoteMediaSnapshot
    /// The entity's `entity_picture`, verbatim. Usually a Home Assistant proxy path whose query is a
    /// signed access token, so it is for fetching through the app's own authenticated connection
    /// and never for logging, persisting or putting in a snapshot.
    public let artworkSource: String?

    init(snapshot: RemoteMediaSnapshot, artworkSource: String?) {
        self.snapshot = snapshot
        self.artworkSource = artworkSource
    }
}
