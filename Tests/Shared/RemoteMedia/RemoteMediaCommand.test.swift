import Foundation
import RemoteMediaCore
import Testing

struct RemoteMediaCommandTests {
    private func snapshot(state: String = "playing") -> RemoteMediaSnapshot {
        .init(
            selection: .init(serverId: "home", entityId: "media_player.echo"),
            deviceName: "Echo", deviceClass: nil, state: state,
            title: "Title", artist: "Artist", album: "Album", contentId: "track",
            duration: 200, position: 10, positionUpdatedAtUnix: 100, artwork: nil,
            volume: 0.5, isMuted: false, features: [.play, .pause, .stop, .seek, .volumeSet]
        )
    }

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

    @Test func serviceNamesMatchHomeAssistant() {
        #expect(RemoteMediaCommand.allCases.map(\.service) == [
            "media_play", "media_pause", "media_play_pause", "media_stop",
            "media_previous_track", "media_next_track", "media_seek", "volume_set",
        ])
    }

    @Test func deterministicCommandsApplyOptimistically() throws {
        let playing = snapshot()
        let paused = try #require(playing.optimisticallyApplying(.pause))
        let toggled = try #require(playing.optimisticallyApplying(.togglePlayPause))
        let resumed = try #require(snapshot(state: "paused").optimisticallyApplying(.play))
        let stopped = try #require(playing.optimisticallyApplying(.stop))
        #expect(paused.state == "paused")
        #expect(toggled.state == "paused")
        #expect(resumed.state == "playing")
        #expect(stopped.state == "idle")

        let sought = try #require(playing.optimisticallyApplying(.seek, value: 42, now: 500))
        #expect(sought.position == 42)
        #expect(sought.positionUpdatedAtUnix == 500)
        let volume = try #require(playing.optimisticallyApplying(.volume, value: 0.25))
        #expect(volume.volume == 0.25)
    }

    @Test func trackChangesAndInvalidValuesAreNotInvented() {
        let playing = snapshot()
        #expect(playing.optimisticallyApplying(.next) == nil)
        #expect(playing.optimisticallyApplying(.previous) == nil)
        #expect(playing.optimisticallyApplying(.seek) == nil)
        #expect(playing.optimisticallyApplying(.volume) == nil)
    }

    @Test func seekAndVolumeAreClampedInThePureModel() throws {
        let playing = snapshot()
        #expect(RemoteMediaCommand.seek.clamped(-5) == 0)
        #expect(RemoteMediaCommand.volume.clamped(2) == 1)
        let sought = try #require(playing.optimisticallyApplying(.seek, value: -5))
        let volume = try #require(playing.optimisticallyApplying(.volume, value: 2))
        #expect(sought.position == 0)
        #expect(volume.volume == 1)
    }
}
