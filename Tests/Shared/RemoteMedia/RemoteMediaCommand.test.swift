import Foundation
@testable import Shared
import Testing

struct RemoteMediaCommandTests {
    @Test func capabilitiesAreIndependent() {
        let pairs: [(RemoteMediaFeatures, RemoteMediaCommand)] = [
            (.play, .play), (.pause, .pause), (.stop, .stop), (.previous, .previous),
            (.next, .next), (.seek, .seek), (.volumeSet, .volume),
        ]
        for (feature, command) in pairs {
            #expect(feature.commands == [command])
        }
        #expect(RemoteMediaFeatures([.play, .pause]).commands == [.play, .pause, .togglePlayPause])
        #expect(RemoteMediaFeatures.volumeMute.commands.isEmpty)
        #expect(RemoteMediaFeatures(rawValue: 128).commands.isEmpty)
    }

    @Test func serviceNamesAndPayloads() throws {
        #expect(RemoteMediaCommand.allCases.map(\.service) == [
            "media_play", "media_pause", "media_play_pause", "media_stop",
            "media_previous_track", "media_next_track", "media_seek", "volume_set",
        ])
        let seek = try RemoteMediaCommand.seek.serviceData(entityId: "media_player.test", value: 42)
        #expect(seek["entity_id"] as? String == "media_player.test")
        #expect(seek["seek_position"] as? Double == 42)
        try #expect(
            RemoteMediaCommand.volume
                .serviceData(entityId: "media_player.test", value: 2)["volume_level"] as? Double == 1
        )
        #expect(throws: RemoteMediaError.self) {
            try RemoteMediaCommand.seek.serviceData(entityId: "media_player.test", value: .nan)
        }
        #expect(throws: RemoteMediaError.self) {
            try RemoteMediaCommand.volume.serviceData(entityId: "media_player.test")
        }
        try #expect(RemoteMediaCommand.pause.serviceData(entityId: "media_player.test").count == 1)
    }
}
