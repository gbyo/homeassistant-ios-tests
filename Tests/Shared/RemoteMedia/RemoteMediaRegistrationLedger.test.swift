import Foundation
@testable import Shared
import Testing

@MainActor
struct RemoteMediaRegistrationLedgerTests {
    private func registration(
        generation: String?,
        token: String = "abcd"
    ) -> RemoteMediaSessionRegistration {
        .init(
            sessionId: "4:homemedia_player.speaker",
            generation: generation,
            entityId: "media_player.speaker",
            pushToken: token
        )
    }

    @Test func theFirstRegistrationOfALifetimeIsSent() {
        let ledger = RemoteMediaRegistrationLedger()
        ledger.adopt(generation: "one")
        #expect(ledger.pending(registration(generation: "one")) != nil)
    }

    @Test func theSameTokenIsNotRegisteredTwice() {
        let ledger = RemoteMediaRegistrationLedger()
        ledger.adopt(generation: "one")
        #expect(ledger.pending(registration(generation: "one")) != nil)
        #expect(ledger.pending(registration(generation: "one")) == nil)
    }

    @Test func aReplacementTokenIsRegistered() {
        let ledger = RemoteMediaRegistrationLedger()
        ledger.adopt(generation: "one")
        #expect(ledger.pending(registration(generation: "one", token: "abcd")) != nil)
        #expect(ledger.pending(registration(generation: "one", token: "efef")) != nil)
    }

    /// Following the same player again reuses the session identifier, so the unchanged token still
    /// has to be registered against the new lifetime.
    @Test func anUnchangedTokenIsRegisteredAgainForANewLifetime() {
        let ledger = RemoteMediaRegistrationLedger()
        ledger.adopt(generation: "one")
        #expect(ledger.pending(registration(generation: "one")) != nil)
        ledger.adopt(generation: "two")
        #expect(ledger.pending(registration(generation: "two")) != nil)
    }

    /// Token delivery is asynchronous: a registration built for the previous lifetime can arrive
    /// after the user has stopped following and followed again.
    @Test func aStragglerFromAnEarlierLifetimeIsDropped() {
        let ledger = RemoteMediaRegistrationLedger()
        ledger.adopt(generation: "one")
        ledger.adopt(generation: "two")
        #expect(ledger.pending(registration(generation: "one")) == nil)
        #expect(ledger.pending(registration(generation: "two")) != nil)
    }

    @Test func adoptingTheSameLifetimeChangesNothing() {
        let ledger = RemoteMediaRegistrationLedger()
        ledger.adopt(generation: "one")
        #expect(ledger.pending(registration(generation: "one")) != nil)
        ledger.adopt(generation: "one")
        #expect(ledger.pending(registration(generation: "one")) == nil)
    }
}
