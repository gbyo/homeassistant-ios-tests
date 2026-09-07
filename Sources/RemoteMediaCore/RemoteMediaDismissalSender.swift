import Foundation

/// Posts one dismissal, and does not care much whether it lands.
///
/// Deliberately weaker than `RemoteMediaRegistrationSender`: there is nothing to keep alive and
/// nothing for the user to wait for, and a dismissal that never arrives self-corrects, because the
/// session it names has already ended and APNs starts rejecting its token. The local session is
/// gone either way — a failure here must never bring the card back.
public struct RemoteMediaDismissalSender: Sendable {
    public typealias Perform = @Sendable (
        RemoteMediaSessionDismissal,
        RemoteMediaTransportContext
    ) async throws -> Void

    public static let live: Perform = { dismissal, context in
        let client = RemoteMediaWebhookClient()
        defer { client.endBurst() }
        try await client.dismiss(dismissal, context: context)
    }

    private let perform: Perform

    public init(perform: @escaping Perform = RemoteMediaDismissalSender.live) {
        self.perform = perform
    }

    /// Sends `end`'s dismissal. One attempt across the routes the client already tries in order.
    public func send(_ end: RemoteMediaFollowEnd) async {
        let dismissal = end.dismissal
        do {
            try await perform(dismissal, end.context)
            RemoteMediaLog.logger.info(
                """
                RemoteMedia dismissal session=\(dismissal.sessionId, privacy: .public) \
                generation=\(dismissal.generation ?? "-", privacy: .public) result=accepted
                """
            )
        } catch {
            RemoteMediaLog.logger.error(
                """
                RemoteMedia dismissal session=\(dismissal.sessionId, privacy: .public) \
                generation=\(dismissal.generation ?? "-", privacy: .public) \
                result=\(error.localizedDescription, privacy: .public)
                """
            )
        }
    }
}
