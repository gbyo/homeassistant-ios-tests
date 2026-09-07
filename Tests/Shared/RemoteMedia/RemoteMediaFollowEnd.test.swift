import Foundation
@testable import Shared
import Testing

/// What a dismissal is built from, and when there is nothing to send.
struct RemoteMediaFollowEndTests {
    private let selection = RemoteMediaSelection(serverId: "home", entityId: "media_player.speaker")

    private func context(for selection: RemoteMediaSelection) -> RemoteMediaTransportContext {
        .init(
            selection: selection,
            webhookURLs: [URL(string: "https://example.com/api/webhook/abc")!],
            secret: Array(repeating: 3, count: 32)
        )
    }

    @Test func theDismissalNamesTheEndingRelationship() throws {
        let end = try #require(RemoteMediaFollowEnd.capture(
            selection: selection,
            generation: "A",
            context: context(for: selection)
        ))
        #expect(end.dismissal.sessionId == selection.id)
        #expect(end.dismissal.generation == "A")
        // The captured transport is the ending relationship's, which is the only one that can
        // authenticate a request about it.
        #expect(end.context.selection == selection)
    }

    /// The generation is the one registered for this Follow lifetime, never a fresh one: Home
    /// Assistant ignores a dismissal that names a lifetime other than the one it has stored.
    @Test func theGenerationIsTheRegisteredOneAndNotAFreshValue() throws {
        let end = try #require(RemoteMediaFollowEnd.capture(
            selection: selection,
            generation: "F1B7D0A2",
            context: context(for: selection)
        ))
        #expect(end.dismissal.generation == "F1B7D0A2")
        let again = try #require(RemoteMediaFollowEnd.capture(
            selection: selection,
            generation: "F1B7D0A2",
            context: context(for: selection)
        ))
        #expect(again.dismissal == end.dismissal)
    }

    @Test func nothingIsOwedWhenNoPlayerWasFollowed() {
        #expect(RemoteMediaFollowEnd.capture(
            selection: nil,
            generation: nil,
            context: context(for: selection)
        ) == nil)
    }

    /// Deleting the server clears the routes and the secret, so there is no longer a way to say
    /// anything about the relationship. Home Assistant drops the token when APNs rejects it.
    @Test func nothingIsOwedWithoutATransport() {
        #expect(RemoteMediaFollowEnd.capture(
            selection: selection,
            generation: "A",
            context: nil
        ) == nil)
    }

    /// Sending one relationship's dismissal with another's transport would authenticate it as that
    /// other relationship.
    @Test func nothingIsOwedWhenTheTransportDescribesAnotherPlayer() {
        #expect(RemoteMediaFollowEnd.capture(
            selection: selection,
            generation: "A",
            context: context(for: .init(serverId: "home", entityId: "media_player.other"))
        ) == nil)
    }

    /// A lifetime that predates generations still gets a dismissal; Home Assistant treats the key
    /// as optional and matches a stored session that also has none.
    @Test func aLifetimeWithoutAGenerationIsStillDismissible() throws {
        let end = try #require(RemoteMediaFollowEnd.capture(
            selection: selection,
            generation: nil,
            context: context(for: selection)
        ))
        #expect(end.dismissal.generation == nil)
    }
}
