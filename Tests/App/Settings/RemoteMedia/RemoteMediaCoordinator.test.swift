#if !targetEnvironment(macCatalyst)
import HAKit
@testable import HomeAssistant
@testable import Shared
import Testing
import UIKit

/// When Home Assistant is told a Follow relationship is over — and, just as importantly, when it
/// is not.
///
/// Following a player means following it until the user says otherwise, so the list of things that
/// must *not* retire the server-side registration is longer than the list of things that must.
///
/// The suite itself carries no `@available`: swift-testing refuses to apply `@Test` to a function
/// marked unavailable, so each test checks at runtime, like the other version-gated suites here.
@MainActor
@Suite(.serialized)
struct RemoteMediaCoordinatorTests {
    @available(iOS 27.0, *)
    private final class Driver: RemoteMediaSessionDriver {
        var snapshots: [RemoteMediaSnapshot?] = []
        func publish(_ snapshot: RemoteMediaSnapshot?) async throws { snapshots.append(snapshot) }
    }

    private final class Dismissals: @unchecked Sendable {
        var sent: [RemoteMediaSessionDismissal] = []
        var contexts: [RemoteMediaTransportContext] = []
        var failure: Error?
        /// Held open so the ordering between ending the local session and the request is visible.
        var block: (() async -> Void)?

        var sender: RemoteMediaDismissalSender {
            .init { [self] dismissal, context in
                await block?()
                sent.append(dismissal)
                contexts.append(context)
                if let failure { throw failure }
            }
        }
    }

    /// Stands in for the Keychain, which the unit test bundle is not entitled to reach.
    private final class MemoryStorage: RemoteMediaSecureStorage, @unchecked Sendable {
        var stored: Data?
        func data() -> Data? { stored }
        func save(_ data: Data) throws { stored = data }
        func clear() { stored = nil }
    }

    private static let speaker = RemoteMediaSelection(serverId: "home", entityId: "media_player.speaker")
    private static let television = RemoteMediaSelection(serverId: "home", entityId: "media_player.tv")

    private func context(for selection: RemoteMediaSelection) -> RemoteMediaTransportContext {
        .init(
            selection: selection,
            webhookURLs: [URL(string: "https://example.com/api/webhook/abc")!],
            secret: Array(repeating: 5, count: 32)
        )
    }

    /// Runs `body` with the coordinator's environment isolated, and puts it back afterwards.
    ///
    /// There is no server registered for `home`, so the coordinator's refresh finds no connection
    /// and publishes nothing — which is exactly the shape this suite wants: the only thing that can
    /// produce a dismissal is `follow`.
    @available(iOS 27.0, *)
    private func withCoordinator(
        following selection: RemoteMediaSelection?,
        _ body: (RemoteMediaCoordinator, Driver, Dismissals, RemoteMediaSessionPublisher) async throws -> Void
    ) async rethrows {
        let store = Current.settingsStore
        let previousSelection = store.remoteMediaSelection
        let previousGeneration = store.remoteMediaSessionGeneration
        let previousStorage = RemoteMediaTransportStore.storage
        RemoteMediaTransportStore.storage = MemoryStorage()
        defer {
            store.remoteMediaSelection = previousSelection
            store.remoteMediaSessionGeneration = previousGeneration
            RemoteMediaTransportStore.storage = previousStorage
        }

        store.remoteMediaSelection = selection
        store.startRemoteMediaSessionGeneration(following: selection)
        if let selection { try? RemoteMediaTransportStore.save(context(for: selection)) }

        let driver = Driver()
        let dismissals = Dismissals()
        let publisher = RemoteMediaSessionPublisher(driver: driver)
        let coordinator = RemoteMediaCoordinator(publisher: publisher, dismissals: dismissals.sender)
        try await body(coordinator, driver, dismissals, publisher)
    }

    private func snapshot(state: String) throws -> RemoteMediaSnapshot {
        let entity = try HAEntity(
            entityId: Self.speaker.entityId, state: state,
            lastChanged: .distantPast, lastUpdated: .distantPast,
            attributes: ["media_title": "Track"],
            context: .init(id: "test", userId: nil, parentId: nil)
        )
        return try #require(RemoteMediaSnapshotMapper.map(entity, serverId: Self.speaker.serverId)).snapshot
    }

    /// The dismissal goes out on a detached task, so the assertions wait for it rather than for a
    /// fixed delay.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    // MARK: - Ending a relationship

    /// The visible "Stop following" button, and the same call behind "Stop following" under an
    /// entity's "Add to".
    @Test func stoppingSendsADismissalNamingTheRelationshipThatEnded() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: Self.speaker) { coordinator, _, dismissals, _ in
            let generation = Current.settingsStore.remoteMediaSessionGeneration
            coordinator.follow(nil)
            await settle()

            #expect(dismissals.sent.count == 1)
            #expect(dismissals.sent.first?.sessionId == Self.speaker.id)
            // The lifetime that was registered, not a fresh one: Home Assistant ignores a dismissal
            // naming any other.
            #expect(dismissals.sent.first?.generation == generation)
            #expect(generation != nil)
            // Sent with the ending relationship's own transport, captured before it was cleared.
            #expect(dismissals.contexts.first?.selection == Self.speaker)
            #expect(RemoteMediaTransportStore.load() == nil)
        }
    }

    /// Stopping is a user action: the card has to go at once, and the request follows it.
    @Test func theLocalSessionEndsWithoutWaitingForTheNetwork() async throws {
        guard #available(iOS 27.0, *) else { return }
        try await withCoordinator(following: Self.speaker) { coordinator, driver, dismissals, _ in
            // A request that has not answered yet, standing in for a phone with no route home.
            dismissals.block = { try? await Task.sleep(for: .milliseconds(200)) }
            coordinator.follow(nil)
            await settle()

            // The session is already gone while the request is still waiting on the network.
            #expect(!driver.snapshots.isEmpty)
            #expect(driver.snapshots.allSatisfy { $0 == nil })
            #expect(dismissals.sent.isEmpty)
            #expect(coordinator.selection == nil)

            try await Task.sleep(for: .milliseconds(400))
            #expect(dismissals.sent.count == 1)
        }
    }

    /// Choosing a different player ends the old relationship and starts a new one; the new lifetime
    /// is never the old one reused.
    @Test func choosingAnotherPlayerDismissesTheOneItReplaced() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: Self.speaker) { coordinator, _, dismissals, _ in
            let first = Current.settingsStore.remoteMediaSessionGeneration
            coordinator.follow(Self.television)
            await settle()

            #expect(dismissals.sent.map(\.sessionId) == [Self.speaker.id])
            #expect(dismissals.sent.first?.generation == first)
            #expect(coordinator.selection == Self.television)
            let second = Current.settingsStore.remoteMediaSessionGeneration
            #expect(second != nil)
            #expect(second != first)
        }
    }

    /// Stopping and immediately following the same player again: same session identifier, two
    /// lifetimes, and the dismissal names the first.
    @Test func stoppingAndFollowingAgainDismissesOnlyTheFirstLifetime() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: Self.speaker) { coordinator, _, dismissals, _ in
            let first = Current.settingsStore.remoteMediaSessionGeneration
            coordinator.follow(nil)
            coordinator.follow(Self.speaker)
            await settle()

            let second = Current.settingsStore.remoteMediaSessionGeneration
            #expect(second != first)
            #expect(dismissals.sent.map(\.generation) == [first])
            // Following again is not blocked by the dismissal of what it replaced.
            #expect(coordinator.selection == Self.speaker)
        }
    }

    @Test func startingToFollowDismissesNothing() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: nil) { coordinator, _, dismissals, _ in
            coordinator.follow(Self.speaker)
            await settle()
            #expect(dismissals.sent.isEmpty)
        }
    }

    /// A dismissal that cannot be delivered changes nothing here. The relationship is over locally
    /// whether or not the server was told.
    @Test func aFailedDismissalDoesNotBringTheCardBack() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: Self.speaker) { coordinator, driver, dismissals, _ in
            dismissals.failure = URLError(.notConnectedToInternet)
            coordinator.follow(nil)
            await settle()

            #expect(dismissals.sent.count == 1)
            #expect(coordinator.selection == nil)
            #expect(Current.settingsStore.remoteMediaSelection == nil)
            #expect(Current.settingsStore.remoteMediaSessionGeneration == nil)
            #expect(driver.snapshots.allSatisfy { $0 == nil })
        }
    }

    // MARK: - Everything that is not the end of a relationship

    /// Foregrounding, reconnecting, a server list change, and Home Assistant being unreachable all
    /// refresh the session. None of them is the user saying they no longer want to follow.
    @Test func refreshingNeverDismisses() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: Self.speaker) { coordinator, _, dismissals, _ in
            let generation = Current.settingsStore.remoteMediaSessionGeneration
            coordinator.refresh()
            coordinator.serversDidChange(Current.servers)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            await settle()

            #expect(dismissals.sent.isEmpty)
            // And the relationship is untouched, so the card comes back when the server does.
            #expect(Current.settingsStore.remoteMediaSelection == Self.speaker)
            #expect(Current.settingsStore.remoteMediaSessionGeneration == generation)
        }
    }

    /// The app going to the background or being torn down, and the extension exiting or being
    /// jetsammed, are not product decisions to stop following — the whole point is that Home
    /// Assistant keeps the card current while none of them is running. None of them has an entry
    /// point here: `didBecomeActiveNotification` is the only lifecycle notification this
    /// coordinator subscribes to, and it refreshes rather than unfollowing, which
    /// `refreshingNeverDismisses` covers. `start()` is the only other way in, and running it
    /// repeatedly — an app relaunch — leaves the relationship exactly as it was.
    @Test func relaunchingTheAppNeverDismisses() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: Self.speaker) { coordinator, _, dismissals, _ in
            let generation = Current.settingsStore.remoteMediaSessionGeneration
            coordinator.start()
            coordinator.start()
            await settle()

            #expect(dismissals.sent.isEmpty)
            #expect(coordinator.selection == Self.speaker)
            #expect(Current.settingsStore.remoteMediaSessionGeneration == generation)
        }
    }

    /// Pausing, going idle between tracks, `media_stop`, being switched off and dropping to
    /// `unavailable` all arrive as ordinary state, which is published and nothing more. An
    /// integration passing through any of them must not retire the registration — that is what
    /// makes the card come back on its own.
    @Test func playbackStateNeverDismisses() async throws {
        guard #available(iOS 27.0, *) else { return }
        try await withCoordinator(following: Self.speaker) { coordinator, driver, dismissals, publisher in
            for state in ["playing", "paused", "idle", "off", "unavailable", "unknown"] {
                try publisher.publish(snapshot(state: state))
                await publisher.waitForPendingUpdates()
            }
            await settle()

            #expect(driver.snapshots.contains { $0 != nil })
            #expect(dismissals.sent.isEmpty)
            #expect(coordinator.selection == Self.speaker)
            #expect(Current.settingsStore.remoteMediaSelection == Self.speaker)
        }
    }

    /// Nothing but a `media_player.` selection, or clearing it, moves the relationship at all — so
    /// a malformed entity cannot become a way to retire someone else's registration.
    @Test func anEntityThatIsNotAPlayerIsIgnoredEntirely() async {
        guard #available(iOS 27.0, *) else { return }
        await withCoordinator(following: Self.speaker) { coordinator, _, dismissals, _ in
            let generation = Current.settingsStore.remoteMediaSessionGeneration
            coordinator.follow(.init(serverId: "home", entityId: "light.kitchen"))
            await settle()

            #expect(dismissals.sent.isEmpty)
            #expect(coordinator.selection == Self.speaker)
            #expect(Current.settingsStore.remoteMediaSessionGeneration == generation)
        }
    }
}
#endif
