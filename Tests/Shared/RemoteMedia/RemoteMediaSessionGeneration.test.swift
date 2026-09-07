import Foundation
@testable import Shared
import Testing

/// A Follow lifetime, which is what tells a token registered for the current relationship apart
/// from one registered for a relationship the user has already ended.
@Suite(.serialized)
struct RemoteMediaSessionGenerationTests {
    private let selection = RemoteMediaSelection(serverId: "home", entityId: "media_player.speaker")

    @Test func aLifetimePersistsUntilFollowingChanges() {
        let store = Current.settingsStore
        let previous = store.remoteMediaSessionGeneration
        defer { store.remoteMediaSessionGeneration = previous }

        let generation = store.startRemoteMediaSessionGeneration(following: selection)
        #expect(generation != nil)
        // Reading it again, and from another store over the same defaults, is the same lifetime.
        #expect(store.remoteMediaSessionGeneration == generation)
        #expect(SettingsStore().remoteMediaSessionGeneration == generation)
    }

    /// Re-following the same player produces the same session identifier, so the lifetime is the
    /// only thing that distinguishes the new relationship from the old one.
    @Test func followingAgainStartsANewLifetime() {
        let store = Current.settingsStore
        let previous = store.remoteMediaSessionGeneration
        defer { store.remoteMediaSessionGeneration = previous }

        let first = store.startRemoteMediaSessionGeneration(following: selection)
        let second = store.startRemoteMediaSessionGeneration(following: selection)
        #expect(first != nil)
        #expect(first != second)
    }

    @Test func stoppingEndsTheLifetime() {
        let store = Current.settingsStore
        let previous = store.remoteMediaSessionGeneration
        defer { store.remoteMediaSessionGeneration = previous }

        store.startRemoteMediaSessionGeneration(following: selection)
        #expect(store.startRemoteMediaSessionGeneration(following: nil) == nil)
        #expect(store.remoteMediaSessionGeneration == nil)
    }
}
