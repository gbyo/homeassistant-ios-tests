import Foundation

/// One `media_player` entity as this feature reads it: the wire-safe snapshot, and the artwork
/// source that must not travel with it.
///
/// `entity_picture` is usually a Home Assistant proxy path carrying a signed token, so it is kept
/// beside `RemoteMediaSnapshot` rather than inside it. Turning it into artwork is the caller's job;
/// only the result belongs in the snapshot.
public struct RemoteMediaEntityState: Equatable, Sendable {
    public let snapshot: RemoteMediaSnapshot
    public let artworkSource: String?

    public init(snapshot: RemoteMediaSnapshot, artworkSource: String?) {
        self.snapshot = snapshot
        self.artworkSource = artworkSource
    }
}
