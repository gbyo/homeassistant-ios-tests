import Foundation
@testable import Shared
import Testing

/// A dismissal is best effort, and its failure must be invisible to everything else.
struct RemoteMediaDismissalSenderTests {
    private let selection = RemoteMediaSelection(serverId: "home", entityId: "media_player.speaker")

    private func end(generation: String? = "A") -> RemoteMediaFollowEnd {
        .init(
            dismissal: .init(sessionId: selection.id, generation: generation),
            context: .init(
                selection: selection,
                webhookURLs: [URL(string: "https://example.com/api/webhook/abc")!],
                secret: nil
            )
        )
    }

    private final class Recorder: @unchecked Sendable {
        var sent: [RemoteMediaSessionDismissal] = []
        var failure: Error?

        var perform: RemoteMediaDismissalSender.Perform {
            { [self] dismissal, _ in
                sent.append(dismissal)
                if let failure { throw failure }
            }
        }
    }

    @Test func theDismissalIsSentOnce() async {
        let recorder = Recorder()
        await RemoteMediaDismissalSender(perform: recorder.perform).send(end())
        #expect(recorder.sent == [.init(sessionId: selection.id, generation: "A")])
    }

    /// Nothing is retried and nothing is thrown: the local session has already ended, and Home
    /// Assistant stops pushing to it anyway once APNs rejects the token.
    @Test func aFailureIsSwallowedAndNotRetried() async {
        let recorder = Recorder()
        recorder.failure = URLError(.notConnectedToInternet)
        await RemoteMediaDismissalSender(perform: recorder.perform).send(end())
        #expect(recorder.sent.count == 1)
    }
}
