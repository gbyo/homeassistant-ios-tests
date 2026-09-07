import Foundation

/// Everything a dismissal needs, captured before the state it needs is torn down.
///
/// Stopping is a user action, so the local session ends immediately and the request goes out
/// afterwards — which means the identity and the transport it depends on have to be taken while
/// they still describe the relationship that is ending. The webhook secret in particular is cleared
/// as part of no longer following, so reading it after the fact would find nothing.
public struct RemoteMediaFollowEnd: Equatable, Sendable {
    public let dismissal: RemoteMediaSessionDismissal
    public let context: RemoteMediaTransportContext

    public init(dismissal: RemoteMediaSessionDismissal, context: RemoteMediaTransportContext) {
        self.dismissal = dismissal
        self.context = context
    }

    /// The relationship that is ending, or `nil` when there is nothing to retire.
    ///
    /// Nothing is owed to the server when no player was being followed, when the routes and secret
    /// it would be sent with are gone — the server the entity lives on having been removed, say —
    /// or when the stored context describes some other player, which would mean sending one
    /// relationship's dismissal authenticated as another's.
    public static func capture(
        selection: RemoteMediaSelection?,
        generation: String?,
        context: RemoteMediaTransportContext?
    ) -> RemoteMediaFollowEnd? {
        guard let selection, let context, context.selection == selection else { return nil }
        return .init(
            dismissal: .init(sessionId: selection.id, generation: generation),
            context: context
        )
    }
}
