import Foundation
import HAKit
@testable import Shared
import Testing

struct RemoteMediaSnapshotMapperTests {
    private func entity(state: String = "playing", attributes: [String: Any] = [:]) throws -> HAEntity {
        try HAEntity(
            entityId: "media_player.speaker",
            state: state,
            lastChanged: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 0),
            attributes: attributes,
            context: .init(id: "test", userId: nil, parentId: nil)
        )
    }

    @Test func completeSong() throws {
        let snapshot = try #require(RemoteMediaSnapshotMapper.map(entity(attributes: [
            "friendly_name": "Living room",
            "media_title": "Track",
            "media_artist": "Artist",
            "media_album_name": "Album",
            "media_content_id": "track-1",
            "media_duration": 180.0,
            "media_position": 42.0,
            "media_position_updated_at": "2026-09-06T12:00:00.123Z",
            "entity_picture": "/api/media_player_proxy/media_player.speaker",
            "volume_level": 0.5,
            "is_volume_muted": false,
            "supported_features": 16387,
        ]), serverId: "home"))
        #expect(snapshot.deviceName == "Living room")
        #expect(snapshot.title == "Track")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.album == "Album")
        #expect(snapshot.contentId == "track-1")
        #expect(snapshot.duration == 180)
        #expect(snapshot.position == 42)
        // Compared as an offset from the whole second: the fractional part does not survive a
        // round trip through `Date` arithmetic exactly, and what matters is that it was parsed.
        let wholeSecond = try #require(ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z"))
        let updatedAt = try #require(snapshot.positionUpdatedAt)
        #expect(abs(updatedAt.timeIntervalSince(wholeSecond) - 0.123) < 0.001)
        #expect(snapshot.artworkPath == "/api/media_player_proxy/media_player.speaker")
        #expect(snapshot.volume == 0.5)
        #expect(snapshot.isMuted == false)
        #expect(snapshot.isActive)
        #expect(snapshot.features.commands == [.play, .pause, .togglePlayPause, .seek])
        try #expect(JSONDecoder().decode(RemoteMediaSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test(arguments: ["playing", "paused", "idle", "off", "unavailable", "unknown"])
    func stateAndMissingMetadata(state: String) throws {
        let snapshot = try #require(RemoteMediaSnapshotMapper.map(entity(state: state), serverId: "home"))
        #expect(snapshot.state == state)
        #expect(snapshot.isActive == ["playing", "paused"].contains(state))
        #expect(snapshot.artist == nil)
        #expect(snapshot.album == nil)
        #expect(snapshot.title == nil)
        #expect(snapshot.artworkPath == nil)
        #expect(snapshot.duration == nil)
        #expect(snapshot.position == nil)
        #expect(snapshot.positionUpdatedAt == nil)
        #expect(snapshot.volume == nil)
        #expect(snapshot.deviceName == "media_player.speaker")
        #expect(snapshot.features.commands.isEmpty)
    }

    @Test func malformedAndOutOfRangeValues() throws {
        let snapshot = try #require(RemoteMediaSnapshotMapper.map(entity(attributes: [
            "media_duration": -1.0, "media_position": -5.0,
            "media_position_updated_at": "not a date", "volume_level": 4.0,
        ]), serverId: "home"))
        #expect(snapshot.duration == nil)
        #expect(snapshot.position == 0)
        #expect(snapshot.positionUpdatedAt == nil)
        #expect(snapshot.volume == 1)
        let bounded = try #require(RemoteMediaSnapshotMapper.map(entity(attributes: [
            "media_duration": 10.0, "media_position": 90.0, "volume_level": -2.0,
        ]), serverId: "home"))
        #expect(bounded.position == 10)
        #expect(bounded.volume == 0)
        let nonfinite = try #require(RemoteMediaSnapshotMapper.map(entity(attributes: [
            "media_duration": Double.infinity, "media_position": Double.nan, "volume_level": Double.nan,
        ]), serverId: "home"))
        #expect(nonfinite.duration == nil)
        #expect(nonfinite.position == nil)
        #expect(nonfinite.volume == nil)
    }

    @Test func stableSessionAndChangingTrack() throws {
        let first = try #require(RemoteMediaSnapshotMapper.map(
            entity(attributes: ["media_title": "One"]),
            serverId: "home"
        ))
        let next = try #require(RemoteMediaSnapshotMapper.map(
            entity(attributes: ["media_title": "Two"]),
            serverId: "home"
        ))
        #expect(first.id == next.id)
        #expect(first.trackId != next.trackId)
        #expect(first.id != RemoteMediaSelection(serverId: "other", entityId: first.selection.entityId).id)
    }

    @Test func timestampWithoutFractions() throws {
        let snapshot = try #require(RemoteMediaSnapshotMapper.map(entity(attributes: [
            "media_position": 1.0, "media_position_updated_at": "2026-09-06T12:00:00Z",
        ]), serverId: "home"))
        #expect(snapshot.positionUpdatedAt != nil)
    }
}
