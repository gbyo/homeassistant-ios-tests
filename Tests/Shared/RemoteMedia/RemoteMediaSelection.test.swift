import Foundation
@testable import Shared
import Testing

@Suite(.serialized)
struct RemoteMediaSelectionTests {
    @Test func selectionPersistsAndCanBeCleared() throws {
        let store = Current.settingsStore
        let previous = store.remoteMediaSelection
        defer { store.remoteMediaSelection = previous }
        let selection = RemoteMediaSelection(serverId: "home", entityId: "media_player.speaker")
        store.remoteMediaSelection = selection
        #expect(SettingsStore().remoteMediaSelection == selection)
        store.remoteMediaSelection = nil
        #expect(SettingsStore().remoteMediaSelection == nil)
    }

    @Test func malformedSelectionIsIgnored() {
        let prefs = Current.settingsStore.prefs
        let previous = prefs.data(forKey: "remoteMediaSelection")
        defer { prefs.set(previous, forKey: "remoteMediaSelection") }
        prefs.set(Data("invalid".utf8), forKey: "remoteMediaSelection")
        #expect(Current.settingsStore.remoteMediaSelection == nil)
    }

    @Test func oldSessionCannotExecuteAfterStopFollowing() async {
        let store = Current.settingsStore
        let previous = store.remoteMediaSelection
        defer { store.remoteMediaSelection = previous }
        store.remoteMediaSelection = nil
        await #expect(throws: RemoteMediaError.self) {
            try await RemoteMediaCommandExecutor().execute(
                .play, selection: .init(serverId: "home", entityId: "media_player.speaker")
            )
        }
    }
}
