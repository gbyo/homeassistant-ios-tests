import Foundation

/// The current Follow relationship, persisted atomically as selection plus lifetime.
public struct RemoteMediaFollowRecord: Codable, Equatable, Sendable {
    public let selection: RemoteMediaSelection
    public let lifetime: RemoteMediaFollowLifetime

    public init(selection: RemoteMediaSelection, lifetime: RemoteMediaFollowLifetime) {
        self.selection = selection
        self.lifetime = lifetime
    }
}
