import Foundation
import RemoteMediaCore
import Testing

struct RemoteMediaSnapshotReducerTests {
    // MARK: - The track: a transition matrix

    /// What was shown before a report arrived.
    enum Previous: String, Sendable {
        case nothing
        /// `track-1`, "Song" by "Artist" on "Album", 200s long, 10s in.
        case identifiedByContentId
        /// "Song", with no content id.
        case titleOnly
        /// "Song" by "Artist", with no content id.
        case titleAndArtist
    }

    /// What the track ends up as, compared field by field.
    struct Expected: Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var contentId: String?
        var duration: TimeInterval?
        var position: TimeInterval?
        var artwork: Artwork
    }

    enum Artwork: Sendable {
        /// The cover prepared for the previous track.
        case previousCover
        /// A different prepared cover, carried by the incoming report.
        case incomingCover
        case deferred
        case absent
    }

    struct Transition: Sendable, CustomTestStringConvertible {
        let name: String
        let previous: Previous
        /// Whether the previous track's cover had been prepared.
        let previousCover: Bool
        let state: String
        /// The incoming report's attributes.
        let incoming: String
        /// Whether the incoming report carries a prepared cover of its own.
        var incomingCover = false
        /// `nil` when there should be no track at all.
        let expected: Expected?

        var testDescription: String { name }
    }

    private static let song = Expected(
        title: "Song", artist: "Artist", album: "Album", contentId: "track-1", duration: 200, position: 10,
        artwork: .previousCover
    )
    private static let proxied = #""entity_picture": "/api/media_player_proxy/x?token=t""#

    static let transitions: [Transition] = [
        // Nothing to show yet.
        .init(
            name: "nothing, then a blank report",
            previous: .nothing,
            previousCover: false,
            state: "idle",
            incoming: "{}",
            expected: nil
        ),
        .init(
            name: "nothing, then a duration alone",
            previous: .nothing,
            previousCover: false,
            state: "playing",
            incoming: #"{"media_duration": 200}"#,
            expected: nil
        ),
        .init(
            name: "nothing, then a content id alone",
            previous: .nothing,
            previousCover: false,
            state: "playing",
            incoming: #"{"media_content_id": "track-1"}"#,
            expected: .init(contentId: "track-1", artwork: .absent)
        ),

        // Reports that identify nothing keep the previous track whole.
        .init(
            name: "a blank report",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "idle",
            incoming: "{}",
            expected: song
        ),
        .init(
            name: "a duration alone",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_duration": 200, "media_position": 30}"#,
            expected: song
        ),
        .init(
            name: "unavailable",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "unavailable",
            incoming: #"{"friendly_name": "Echo"}"#,
            expected: song
        ),
        .init(
            name: "unknown",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "unknown",
            incoming: "{}",
            expected: song
        ),

        // The same content id: metadata that is missing is incomplete, not different.
        .init(
            name: "same content id, metadata gone",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_content_id": "track-1", \#(proxied)}"#,
            expected: song
        ),
        .init(
            name: "same content id, metadata and picture gone",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_content_id": "track-1"}"#,
            expected: song
        ),
        .init(
            name: "same content id and title, more to say",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "paused",
            incoming: #"""
            {"media_content_id": "track-1", "media_title": "Song", "media_position": 50,
             "media_position_updated_at": "2026-09-06T12:00:40+00:00"}
            """#,
            expected: with(song) { $0.position = 50 }
        ),
        .init(
            name: "same content id, a newer cover",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_content_id": "track-1"}"#,
            incomingCover: true,
            expected: with(song) { $0.artwork = .incomingCover }
        ),
        .init(
            name: "same content id, first sign of a cover",
            previous: .identifiedByContentId,
            previousCover: false,
            state: "playing",
            incoming: #"{"media_content_id": "track-1", \#(proxied)}"#,
            expected: with(song) { $0.artwork = .deferred }
        ),

        // The same content id with conflicting metadata: a stream that keeps one id across songs.
        .init(
            name: "same content id, new title",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_content_id": "track-1", "media_title": "Next", \#(proxied)}"#,
            expected: .init(title: "Next", contentId: "track-1", artwork: .deferred)
        ),
        .init(
            name: "same content id, new artist",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_content_id": "track-1", "media_artist": "Other"}"#,
            expected: .init(artist: "Other", contentId: "track-1", artwork: .absent)
        ),

        // A different content id is a different track, whatever else agrees.
        .init(
            name: "new content id, same title",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_content_id": "track-2", "media_title": "Song", \#(proxied)}"#,
            expected: .init(title: "Song", contentId: "track-2", artwork: .deferred)
        ),

        // Without a content id on one side, agreeing metadata is the evidence, in either direction.
        .init(
            name: "content id dropped, same title",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_title": "Song"}"#,
            expected: song
        ),
        .init(
            name: "content id appears, same title",
            previous: .titleOnly,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_content_id": "track-1", "media_title": "Song"}"#,
            expected: .init(title: "Song", contentId: "track-1", artwork: .previousCover)
        ),
        .init(
            name: "no content id, same artist",
            previous: .titleAndArtist,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_artist": "Artist", "media_album_name": "Album"}"#,
            expected: .init(title: "Song", artist: "Artist", album: "Album", artwork: .previousCover)
        ),
        .init(
            name: "no content id, metadata arriving",
            previous: .titleOnly,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_title": "Song", "media_artist": "Artist", \#(proxied)}"#,
            expected: .init(title: "Song", artist: "Artist", artwork: .previousCover)
        ),
        .init(
            name: "no content id, metadata leaving",
            previous: .titleAndArtist,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_title": "Song"}"#,
            expected: .init(title: "Song", artist: "Artist", artwork: .previousCover)
        ),
        .init(
            name: "no content id, new title",
            previous: .titleAndArtist,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_title": "Two", "media_artist": "Artist", \#(proxied)}"#,
            expected: .init(title: "Two", artist: "Artist", artwork: .deferred)
        ),
        // Nothing in common is not evidence of the same track.
        .init(
            name: "content id dropped, unrelated metadata",
            previous: .identifiedByContentId,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_album_name": "Other Album"}"#,
            expected: .init(album: "Other Album", artwork: .absent)
        ),
        .init(
            name: "no content id, unrelated metadata",
            previous: .titleOnly,
            previousCover: true,
            state: "playing",
            incoming: #"{"media_artist": "Artist", \#(proxied)}"#,
            expected: .init(artist: "Artist", artwork: .deferred)
        ),
    ]

    private static func with(_ expected: Expected, _ change: (inout Expected) -> Void) -> Expected {
        var expected = expected
        change(&expected)
        return expected
    }

    @Test(arguments: transitions)
    func trackTransitions(_ transition: Transition) throws {
        var previous: RemoteMediaSnapshot?
        switch transition.previous {
        case .nothing:
            previous = nil
        case .identifiedByContentId:
            previous = try report("playing", #"""
            {"media_content_id": "track-1", "media_title": "Song", "media_artist": "Artist",
             "media_album_name": "Album", "media_duration": 200, "media_position": 10,
             "media_position_updated_at": "2026-09-06T12:00:00+00:00", \#(Self.proxied)}
            """#)
        case .titleOnly:
            previous = try report("playing", #"{"media_title": "Song", \#(Self.proxied)}"#)
        case .titleAndArtist:
            previous = try report("playing", #"{"media_title": "Song", "media_artist": "Artist", \#(Self.proxied)}"#)
        }
        if transition.previousCover, let shown = previous {
            previous = try withCover(shown, key: Self.coverKey)
        }
        var incoming = try report(transition.state, transition.incoming)
        if transition.incomingCover {
            incoming = try withCover(incoming, key: Self.otherCoverKey)
        }

        let track = reduce(previous, incoming).track
        guard let expected = transition.expected else {
            #expect(track == nil)
            return
        }
        let actual = try #require(track)
        let contentKey = try expected.contentId.map { contentId in
            try #require(report("playing", #"{"media_content_id": "\#(contentId)"}"#).track?.contentKey)
        }
        #expect(actual.title == expected.title)
        #expect(actual.artist == expected.artist)
        #expect(actual.album == expected.album)
        #expect(actual.contentKey == contentKey)
        #expect(actual.duration == expected.duration)
        #expect(actual.position == expected.position)
        // A timestamp only ever travels with the position it dates.
        #expect((actual.positionUpdatedAtUnix != nil) == (expected.position != nil))
        let artwork: RemoteMediaArtwork = switch expected.artwork {
        case .previousCover: try cover(Self.coverKey)
        case .incomingCover: try cover(Self.otherCoverKey)
        case .deferred: .deferred
        case .absent: .absent
        }
        #expect(actual.artwork == artwork)
    }

    // MARK: - The player

    /// Keeping the old song on screen is no reason to keep the old name, volume or controls.
    @Test func aReportWithoutATrackStillUpdatesThePlayer() throws {
        let previous = try report("playing", Self.player)
        let incoming = try report("idle", #"""
        {"friendly_name": "Kitchen Echo", "device_class": "speaker", "volume_level": 0.9, "supported_features": 4}
        """#)
        let result = reduce(previous, incoming)
        #expect(result.track == previous.track)
        #expect(result.player.name == "Kitchen Echo")
        #expect(result.player.deviceClass == "speaker")
        #expect(result.player.volume == 0.9)
        #expect(result.player.features == .volumeSet)
        #expect(result.player.playback == .stopped)
    }

    @Test func theSameTrackStillUpdatesThePlayer() throws {
        let previous = try report("playing", Self.player)
        let incoming = try report("paused", #"""
        {"friendly_name": "Echo", "volume_level": 0.2, "supported_features": 16387, "media_title": "Song"}
        """#)
        let result = reduce(previous, incoming)
        #expect(result.player.playback == .paused)
        #expect(result.player.volume == 0.2)
        #expect(result.player.features == [.play, .pause, .seek])
    }

    @Test func aReportWithoutAVolumeHasNoVolume() throws {
        let previous = try report("playing", Self.player)
        let result = try reduce(previous, report("idle", #"{"friendly_name": "Echo"}"#))
        #expect(result.player.volume == nil)
        #expect(result.player.features.isEmpty)
    }

    /// Not reporting is not the same as having stopped, so the last known playback state stands —
    /// while everything else about the player still follows the report.
    @Test(arguments: ["unavailable", "unknown"])
    func anIndeterminateReportKeepsThePreviousPlaybackState(_ state: String) throws {
        let previous = try report("paused", Self.player)
        let incoming = try report(state, #"{"friendly_name": "Echo", "supported_features": 1}"#)
        let result = reduce(previous, incoming)
        #expect(result.player.playback == .paused)
        #expect(result.player.volume == nil)
        #expect(result.player.features == .pause)
    }

    @Test func anIndeterminateReportWithNothingBeforeItStaysIndeterminate() throws {
        let result = try reduce(nil, report("unavailable", "{}"))
        #expect(result.player.playback == .indeterminate)
        #expect(result.track == nil)
    }

    // MARK: - Positions

    /// A position and the moment it was measured are one fact; a report without one keeps both.
    @Test func theSameTrackWithoutAPositionKeepsThePreviousPositionAndItsTimestamp() throws {
        let previous = try report("playing", Self.player)
        let incoming = try report("playing", #"{"media_title": "Song", "media_position": true}"#)
        let track = try #require(reduce(previous, incoming).track)
        #expect(track.position == 10)
        #expect(track.positionUpdatedAtUnix == 1_788_696_000)
    }

    @Test func theSameTrackWithANewPositionTakesItsTimestampToo() throws {
        let previous = try report("playing", Self.player)
        let incoming = try report("playing", #"""
        {"media_title": "Song", "media_position": 90, "media_position_updated_at": "2026-09-06T12:01:20+00:00"}
        """#)
        let track = try #require(reduce(previous, incoming).track)
        #expect(track.position == 90)
        #expect(track.positionUpdatedAtUnix == 1_788_696_080)
        #expect(track.duration == 200)
    }

    @Test func aNewPositionWithoutATimestampDropsTheOldTimestamp() throws {
        let previous = try report("playing", Self.player)
        let incoming = try report("playing", #"{"media_title": "Song", "media_position": 90}"#)
        let track = try #require(reduce(previous, incoming).track)
        #expect(track.position == 90)
        #expect(track.positionUpdatedAtUnix == nil)
    }

    // MARK: - Helpers

    private static let player = #"""
    {
        "friendly_name": "Echo", "volume_level": 0.5, "supported_features": 16435,
        "media_title": "Song", "media_duration": 200, "media_position": 10,
        "media_position_updated_at": "2026-09-06T12:00:00+00:00"
    }
    """#

    private static let coverKey = String(repeating: "a", count: 64)
    private static let otherCoverKey = String(repeating: "b", count: 64)

    private func reduce(_ previous: RemoteMediaSnapshot?, _ incoming: RemoteMediaSnapshot) -> RemoteMediaSnapshot {
        RemoteMediaSnapshotReducer.reduce(previous: previous, incoming: incoming)
    }

    private func report(_ state: String = "playing", _ json: String) throws -> RemoteMediaSnapshot {
        try RemoteMediaFixtures.report(state, json)
    }

    /// `snapshot` once its cover has been prepared, built the way it reaches a consumer: as the wire
    /// form, with the artwork filled in.
    private func withCover(_ snapshot: RemoteMediaSnapshot, key: String) throws -> RemoteMediaSnapshot {
        var object = try RemoteMediaFixtures.jsonObject(snapshot)
        var track = try #require(object["track"] as? [String: Any])
        track["artwork"] = ["state": "available", "cacheKey": key]
        object["track"] = track
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(RemoteMediaSnapshot.self, from: data)
    }

    private func cover(_ key: String) throws -> RemoteMediaArtwork {
        try RemoteMediaFixtures.decode(RemoteMediaArtwork.self, #"{"state": "available", "cacheKey": "\#(key)"}"#)
    }
}
