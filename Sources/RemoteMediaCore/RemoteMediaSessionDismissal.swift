import Foundation

/// Tells Home Assistant that a Follow relationship is over, so the token registered for it can be
/// dropped rather than left to age out.
///
/// The generation is what makes this safe to act on: stopping and immediately re-following the same
/// player produces a new lifetime, and a dismissal for the previous one must not take the new one's
/// token with it.
public struct RemoteMediaSessionDismissal: Codable, Equatable, Sendable {
    public let sessionId: String
    public let generation: String?

    public init(sessionId: String, generation: String?) {
        self.sessionId = sessionId
        self.generation = generation
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case generation
    }
}
