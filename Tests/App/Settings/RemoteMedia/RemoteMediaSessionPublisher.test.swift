#if !targetEnvironment(macCatalyst)
import HAKit
@testable import HomeAssistant
@testable import Shared
import Testing

/// The suite itself carries no `@available`: swift-testing refuses to apply `@Test` to a function
/// marked unavailable, so each test checks at runtime, like the other version-gated suites here.
@MainActor
struct RemoteMediaSessionPublisherTests {
    @available(iOS 27.0, *)
    private final class Driver: RemoteMediaSessionDriver {
        var snapshots: [RemoteMediaSnapshot?] = []
        var duringPublish: (() -> Void)?
        var shouldFail = false

        func publish(_ snapshot: RemoteMediaSnapshot?) async throws {
            snapshots.append(snapshot)
            duringPublish?()
            if shouldFail { throw RemoteMediaError.unavailable }
        }
    }

    private func snapshot(state: String = "playing", title: String = "Track") throws -> RemoteMediaSnapshot {
        let entity = try HAEntity(
            entityId: "media_player.speaker", state: state,
            lastChanged: .distantPast, lastUpdated: .distantPast,
            attributes: ["media_title": title],
            context: .init(id: "test", userId: nil, parentId: nil)
        )
        return try #require(RemoteMediaSnapshotMapper.map(entity, serverId: "home"))
    }

    @Test func playTrackChangePauseAndStop() async throws {
        guard #available(iOS 27.0, *) else { return }
        let driver = Driver()
        let publisher = RemoteMediaSessionPublisher(driver: driver)
        let playing = try snapshot()
        let next = try snapshot(title: "Next")
        let paused = try snapshot(state: "paused", title: "Next")
        for value in [playing, next, paused] {
            publisher.publish(value)
            await publisher.waitForPendingUpdates()
        }
        publisher.publish(nil)
        await publisher.waitForPendingUpdates()
        #expect(driver.snapshots == [playing, next, paused, nil])
    }

    @Test(arguments: ["idle", "off", "unavailable", "unknown"])
    func inactiveEndsSession(state: String) async throws {
        guard #available(iOS 27.0, *) else { return }
        let driver = Driver()
        let publisher = RemoteMediaSessionPublisher(driver: driver)
        try publisher.publish(snapshot(state: state))
        await publisher.waitForPendingUpdates()
        #expect(driver.snapshots.count == 1)
        #expect(driver.snapshots[0] == nil)
    }

    @Test func stopArrivingDuringStartIsNotLost() async throws {
        guard #available(iOS 27.0, *) else { return }
        let driver = Driver()
        let publisher = RemoteMediaSessionPublisher(driver: driver)
        driver.duringPublish = {
            driver.duringPublish = nil
            publisher.publish(nil)
        }
        try publisher.publish(snapshot())
        await publisher.waitForPendingUpdates()
        #expect(driver.snapshots.count == 2)
        #expect(driver.snapshots[0] != nil)
        #expect(driver.snapshots[1] == nil)
    }

    @Test func failureAllowsLaterUpdate() async throws {
        guard #available(iOS 27.0, *) else { return }
        let driver = Driver()
        let publisher = RemoteMediaSessionPublisher(driver: driver)
        var hadError = false
        publisher.onError = { hadError = $0 != nil }
        driver.shouldFail = true
        try publisher.publish(snapshot())
        await publisher.waitForPendingUpdates()
        #expect(hadError)
        driver.shouldFail = false
        try publisher.publish(snapshot(state: "paused"))
        await publisher.waitForPendingUpdates()
        #expect(!hadError)
        #expect(driver.snapshots.count == 2)
    }
}
#endif
