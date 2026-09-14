import Foundation

/// A server-authoritative entity rename observed by the RemoteMedia extension.
///
/// This contains relationship identity only. Credentials remain in the shared Keychain context.
public struct RemoteMediaAuthoritativeSelection: Codable, Equatable, Sendable {
    public let sessionId: String
    public let generation: String
    public let generationSequence: Int
    public let selection: RemoteMediaSelection

    public init(
        sessionId: String,
        lifetime: RemoteMediaFollowLifetime,
        selection: RemoteMediaSelection
    ) {
        self.sessionId = sessionId
        self.generation = lifetime.generation
        self.generationSequence = lifetime.sequence
        self.selection = selection
    }

    public var lifetime: RemoteMediaFollowLifetime {
        .init(generation: generation, sequence: generationSequence)
    }
}
