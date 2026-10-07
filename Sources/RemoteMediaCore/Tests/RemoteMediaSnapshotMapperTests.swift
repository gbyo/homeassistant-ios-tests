import Foundation
import RemoteMediaCore
import Testing

struct RemoteMediaSnapshotMapperTests {
    @Test func aCompleteSong() throws {
        let mapped = try RemoteMediaFixtures.mapped("playing", #"""
        {
            "friendly_name": "Living room",
            "device_class": "speaker",
            "media_title": "Song",
            "media_artist": "Artist",
            "media_album_name": "Album",
            "media_content_id": "abc",
            "media_duration": 180,
            "media_position": 42.5,
            "media_position_updated_at": "2026-09-06T12:00:00.123456+00:00",
            "entity_picture": "/api/media_player_proxy/media_player.living_room?token=secret&cache=1",
            "volume_level": 0.5,
            "is_volume_muted": false,
            "supported_features": 16387
        }
        """#)
        let player = mapped.snapshot.player
        #expect(player.name == "Living room")
        #expect(player.deviceClass == "speaker")
        #expect(player.playback == .playing)
        #expect(player.volume == 0.5)
        #expect(player.features == [.play, .pause, .seek])

        let track = try #require(mapped.snapshot.track)
        #expect(track.title == "Song")
        #expect(track.artist == "Artist")
        #expect(track.album == "Album")
        // `hashlib.sha256(b"abc").hexdigest()`: what a server computes for the same content id.
        #expect(track.contentKey?.hexString == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(track.duration == 180)
        #expect(track.position == 42.5)
        let updatedAt = try #require(track.positionUpdatedAtUnix)
        #expect(abs(updatedAt - 1_788_696_000.123456) < 0.000_001)
        // A proxy path: a cover exists, but only the app's own connection can fetch it.
        #expect(track.artwork == .deferred)
        #expect(mapped.artworkSource == "/api/media_player_proxy/media_player.living_room?token=secret&cache=1")
    }

    @Test func anEntityReportingNothingHasNoTrack() throws {
        let mapped = try RemoteMediaFixtures.mapped("idle")
        #expect(mapped.snapshot.track == nil)
        #expect(mapped.snapshot.player.name == "media_player.living_room")
        #expect(mapped.snapshot.player.playback == .stopped)
        #expect(mapped.snapshot.player.volume == nil)
        #expect(mapped.snapshot.player.features.isEmpty)
        #expect(mapped.artworkSource == nil)
    }

    @Test(arguments: [
        ("playing", RemoteMediaPlaybackState.playing),
        ("paused", .paused),
        ("buffering", .buffering),
        ("idle", .stopped),
        ("on", .stopped),
        ("off", .stopped),
        ("standby", .stopped),
        ("unavailable", .indeterminate),
        ("unknown", .indeterminate),
        ("Playing", .indeterminate),
        ("", .indeterminate),
    ])
    func homeAssistantStates(_ state: String, _ playback: RemoteMediaPlaybackState) throws {
        let report = try RemoteMediaFixtures.report(state)
        #expect(report.player.playback == playback)
    }

    // MARK: - Strings

    /// Matches a server's `_non_empty(friendly_name) or entity_id`: an empty name is a missing name.
    @Test(arguments: [#"{"friendly_name": ""}"#, #"{"friendly_name": null}"#, #"{"friendly_name": 7}"#, "{}"])
    func aMissingOrUnusableFriendlyNameFallsBackToTheEntityId(_ json: String) throws {
        let report = try RemoteMediaFixtures.report("idle", json)
        #expect(report.player.name == "media_player.living_room")
    }

    /// Each empty value is a missing one; the title alone keeps the track.
    @Test func emptyStringsAreMissingValues() throws {
        let mapped = try RemoteMediaFixtures.mapped("playing", #"""
        {"device_class": "", "media_title": "Song", "media_artist": "", "media_album_name": "",
         "media_content_id": "", "entity_picture": ""}
        """#)
        #expect(mapped.snapshot.player.deviceClass == nil)
        let track = try #require(mapped.snapshot.track)
        #expect(track.title == "Song")
        #expect(track.artist == nil)
        #expect(track.album == nil)
        #expect(track.contentKey == nil)
        #expect(track.artwork == .absent)
        #expect(mapped.artworkSource == nil)
    }

    @Test func nonStringMetadataIsMissing() throws {
        let track = try RemoteMediaFixtures.report("playing", #"""
        {"media_title": "Song", "media_artist": true, "media_album_name": ["Album"], "media_content_id": 12}
        """#).track
        #expect(track?.title == "Song")
        #expect(track?.artist == nil)
        #expect(track?.album == nil)
        #expect(track?.contentKey == nil)
    }

    // MARK: - What makes a track

    /// Only a title, artist, album or content id identifies media. Everything else describes a track
    /// already identified, and players report it on its own while changing track.
    @Test(arguments: [
        #"{"media_duration": 200}"#,
        #"{"media_position": 12}"#,
        #"{"media_duration": 200, "media_position": 12, "media_position_updated_at": "2026-09-06T12:00:00Z"}"#,
        #"{"entity_picture": "/api/media_player_proxy/media_player.living_room?token=t"}"#,
        #"{"media_duration": 200, "entity_picture": "/api/media_player_proxy/x?token=t", "volume_level": 0.4}"#,
        #"{"media_title": "", "media_content_id": "", "media_duration": 200}"#,
        #"{"media_title": 1, "media_artist": true, "media_content_id": 12, "media_duration": 200}"#,
        #"{"media_series_title": "Show", "media_channel": "BBC One", "app_name": "Plex"}"#,
    ])
    func unidentifiedMediaIsNoTrack(_ json: String) throws {
        let report = try RemoteMediaFixtures.report("playing", json)
        #expect(report.track == nil)
    }

    @Test(arguments: [
        #"{"media_title": "Song", "media_duration": 200}"#,
        #"{"media_artist": "Artist", "media_duration": 200}"#,
        #"{"media_album_name": "Album", "media_duration": 200}"#,
        #"{"media_content_id": "abc", "media_duration": 200}"#,
    ])
    func anyIdentifyingValueMakesATrack(_ json: String) throws {
        let report = try RemoteMediaFixtures.report("playing", json)
        let track = try #require(report.track)
        #expect(track.duration == 200)
    }

    // MARK: - Numbers

    /// Foundation bridges booleans through `NSNumber`, which would happily read `true` as `1`. None of
    /// these is a number.
    @Test(arguments: [
        #"{"media_title": "Song", "media_duration": true}"#,
        #"{"media_title": "Song", "media_duration": false}"#,
    ])
    func aBooleanIsNotADuration(_ json: String) throws {
        let report = try RemoteMediaFixtures.report("playing", json)
        let track = try #require(report.track)
        #expect(track.duration == nil)
    }

    @Test(arguments: [
        #"{"media_title": "Song", "media_duration": 100, "media_position": true}"#,
        #"{"media_title": "Song", "media_duration": 100, "media_position": false}"#,
    ])
    func aBooleanIsNotAPosition(_ json: String) throws {
        let report = try RemoteMediaFixtures.report("playing", json)
        let track = try #require(report.track)
        #expect(track.position == nil)
    }

    @Test(arguments: [#"{"volume_level": true}"#, #"{"volume_level": false}"#])
    func aBooleanIsNotAVolume(_ json: String) throws {
        let report = try RemoteMediaFixtures.report("playing", json)
        #expect(report.player.volume == nil)
    }

    /// The same rules hold for values built in Swift rather than parsed from JSON.
    @Test func swiftValuesFollowTheSameRules() throws {
        let entityId = try RemoteMediaFixtures.entityId
        let booleans = RemoteMediaSnapshotMapper.map(entityId: entityId, state: "playing", attributes: [
            "media_title": "Song", "media_duration": true, "media_position": false, "volume_level": true,
            "supported_features": true,
        ]).snapshot
        #expect(booleans.track?.duration == nil)
        #expect(booleans.track?.position == nil)
        #expect(booleans.player.volume == nil)
        #expect(booleans.player.features.isEmpty)

        let numbers = RemoteMediaSnapshotMapper.map(entityId: entityId, state: "playing", attributes: [
            "media_title": "Song", "media_duration": 100, "media_position": 10.5, "volume_level": 1,
            "supported_features": 1,
        ]).snapshot
        #expect(numbers.track?.duration == 100)
        #expect(numbers.track?.position == 10.5)
        #expect(numbers.player.volume == 1)
        #expect(numbers.player.features == .pause)

        let nonFinite = RemoteMediaSnapshotMapper.map(entityId: entityId, state: "playing", attributes: [
            "media_title": "Song", "media_duration": Double.infinity, "media_position": Double.nan,
            "volume_level": -Double.infinity,
        ]).snapshot
        #expect(nonFinite.track?.duration == nil)
        #expect(nonFinite.track?.position == nil)
        #expect(nonFinite.player.volume == nil)
    }

    @Test func numericStringsAreNotNumbers() throws {
        let report = try RemoteMediaFixtures.report("playing", #"""
        {"media_title": "Song", "media_duration": "180", "media_position": "4", "volume_level": "0.5"}
        """#)
        #expect(report.track?.duration == nil)
        #expect(report.track?.position == nil)
        #expect(report.player.volume == nil)
    }

    @Test func outOfRangeValuesAreClamped() throws {
        let unbounded = try RemoteMediaFixtures.report("playing", #"""
        {"media_title": "Song", "media_duration": -1, "media_position": -5, "volume_level": 4}
        """#)
        #expect(unbounded.track?.duration == nil)
        #expect(unbounded.track?.position == 0)
        #expect(unbounded.player.volume == 1)

        let bounded = try RemoteMediaFixtures.report("playing", #"""
        {"media_title": "Song", "media_duration": 10, "media_position": 90, "volume_level": -2}
        """#)
        #expect(bounded.track?.position == 10)
        #expect(bounded.player.volume == 0)
    }

    @Test func aZeroDurationIsNoDuration() throws {
        let report = try RemoteMediaFixtures.report("playing", #"{"media_title": "Song", "media_duration": 0}"#)
        #expect(report.track?.duration == nil)
    }

    // MARK: - Position timestamps

    @Test func aTimestampWithoutAPositionIsDropped() throws {
        let track = try RemoteMediaFixtures.report("playing", #"""
        {"media_title": "Song", "media_position_updated_at": "2026-09-06T12:00:00+00:00"}
        """#).track
        #expect(track?.position == nil)
        #expect(track?.positionUpdatedAtUnix == nil)
    }

    @Test func aPositionWithoutAUsableTimestampIsKept() throws {
        let track = try RemoteMediaFixtures.report("playing", #"""
        {"media_title": "Song", "media_position": 5, "media_position_updated_at": 1788696000}
        """#).track
        #expect(track?.position == 5)
        #expect(track?.positionUpdatedAtUnix == nil)
    }

    // MARK: - Artwork

    @Test func noEntityPictureIsNoArtwork() throws {
        let mapped = try RemoteMediaFixtures.mapped("playing", #"{"media_title": "Song"}"#)
        #expect(mapped.snapshot.track?.artwork == .absent)
        #expect(mapped.artworkSource == nil)
    }

    /// The snapshot says only that a cover exists, whatever the picture looks like. Even a public
    /// HTTPS URL stays beside it: it can name a self-hosted server, and the app can always fetch the
    /// picture through its own connection, so there is nothing the wire needs it for.
    @Test(arguments: [
        "/api/media_player_proxy/media_player.living_room?token=secret&cache=1",
        "https://i.scdn.co/image/ab67616d0000b273",
        "https://jellyfin.example.com/Items/42/Images/Primary",
        "https://i.scdn.co/image/cover.jpg?token=secret",
        "https://user:password@media.example.com/cover.jpg",
        "http://192.168.1.20:32400/photo/cover.jpg",
        "local/covers/cover.jpg",
    ])
    func anyPictureIsDeferredArtwork(_ picture: String) throws {
        let entityId = try RemoteMediaFixtures.entityId
        let mapped = RemoteMediaSnapshotMapper.map(
            entityId: entityId,
            state: "playing",
            attributes: ["media_title": "Song", "entity_picture": picture]
        )
        #expect(mapped.snapshot.track?.artwork == .deferred)
        #expect(mapped.artworkSource == picture)
    }

    /// Only the snapshot has a wire form. The values kept beside it cannot be encoded by accident.
    @Test func theEntityStateItselfIsNotEncodable() throws {
        let mapped = try RemoteMediaFixtures.mapped("playing", #"{"media_title": "Song"}"#)
        #expect(!((mapped as Any) is any Encodable))
    }
}
