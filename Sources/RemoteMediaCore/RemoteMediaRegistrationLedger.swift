import Foundation

/// Decides whether a push token still needs telling the server about.
///
/// Two things have to be true before a registration goes out: it has to say something new, and it
/// has to describe the Follow lifetime the session is actually in. Token delivery is asynchronous,
/// so a registration built while the previous lifetime was current can arrive after the user has
/// stopped following and followed again — registering it then would hand the server a token for a
/// session it has already replaced.
@MainActor
public final class RemoteMediaRegistrationLedger {
    private var generation: String?
    private var sent: RemoteMediaSessionRegistration?

    public init() {}

    /// Adopts the Follow lifetime the newest attributes describe. A change means whatever was
    /// registered belongs to a session that is over, so the current token is registered again.
    public func adopt(generation: String?) {
        guard generation != self.generation else { return }
        self.generation = generation
        sent = nil
    }

    /// The registration to send, or `nil` when there is nothing new to say.
    public func pending(_ registration: RemoteMediaSessionRegistration) -> RemoteMediaSessionRegistration? {
        guard registration.generation == generation else { return nil }
        guard registration != sent else { return nil }
        sent = registration
        return registration
    }

    /// Puts a registration back, so the next thing that would have offered it does.
    ///
    /// For the case where the request never reached anyone: the token is still owed to the server,
    /// and the host app publishing the next state change is a free chance to try again. A server
    /// that answered and refused is deliberately not released — repeating a request the server has
    /// already read and rejected would turn every state change into a pointless POST.
    public func release(_ registration: RemoteMediaSessionRegistration) {
        guard sent == registration else { return }
        sent = nil
    }
}
