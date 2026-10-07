import Foundation
import RemoteMediaCore
import Testing

/// The snapshot as a protocol, not as a Swift type: literal JSON a server would send, and the literal
/// JSON this side writes. A round trip through `JSONEncoder` and `JSONDecoder` alone would only prove
/// that Swift agrees with itself.
struct RemoteMediaSnapshotWireTests {
    /// `hashlib.sha256(b"abc").hexdigest()`.
    static let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    private static let complete = #"""
    {
        "player": {
            "name": "Living room",
            "deviceClass": "speaker",
            "playback": "playing",
            "volume": 0.5,
            "features": 16387
        },
        "track": {
            "title": "Song",
            "artist": "Artist",
            "album": "Album",
            "contentKey": "\#(digest)",
            "duration": 180,
            "position": 42.5,
            "positionUpdatedAtUnix": 1788696000.25,
            "artwork": {"state": "available", "url": "https://cdn.example.com/cover.jpg"}
        }
    }
    """#

    private func decode(_ json: String) throws -> RemoteMediaSnapshot {
        try RemoteMediaFixtures.decode(RemoteMediaSnapshot.self, json)
    }

    // MARK: - Decoding what a server sends

    @Test func aCompleteSnapshot() throws {
        let snapshot = try decode(Self.complete)
        #expect(snapshot.player.name == "Living room")
        #expect(snapshot.player.deviceClass == "speaker")
        #expect(snapshot.player.playback == .playing)
        #expect(snapshot.player.volume == 0.5)
        #expect(snapshot.player.features == [.play, .pause, .seek])
        let track = try #require(snapshot.track)
        #expect(track.title == "Song")
        #expect(track.artist == "Artist")
        #expect(track.album == "Album")
        #expect(track.contentKey?.hexString == Self.digest)
        #expect(track.duration == 180)
        #expect(track.position == 42.5)
        // Unix seconds, read as they are: not `Date`'s 2001 reference epoch.
        #expect(track.positionUpdatedAtUnix == 1_788_696_000.25)
        guard case let .available(.remote(artworkURL)) = track.artwork else {
            Issue.record("Expected remote artwork")
            return
        }
        #expect(artworkURL.url.absoluteString == "https://cdn.example.com/cover.jpg")
    }

    /// Everything optional is omitted: a player with nothing playing.
    @Test func aMinimalSnapshot() throws {
        let snapshot = try decode(#"{"player": {"name": "Kitchen", "playback": "stopped", "features": 0}}"#)
        #expect(snapshot.player.name == "Kitchen")
        #expect(snapshot.player.deviceClass == nil)
        #expect(snapshot.player.playback == .stopped)
        #expect(snapshot.player.volume == nil)
        #expect(snapshot.player.features.isEmpty)
        #expect(snapshot.track == nil)
        let explicitNull = try decode(#"""
        {"player": {"name": "Kitchen", "playback": "stopped", "features": 0}, "track": null}
        """#)
        #expect(explicitNull == snapshot)
    }

    @Test func aMinimalTrack() throws {
        let snapshot = try decode(#"""
        {"player": {"name": "Kitchen", "playback": "paused", "features": 1},
         "track": {"title": "Song", "artwork": {"state": "absent"}}}
        """#)
        let track = try #require(snapshot.track)
        #expect(track.title == "Song")
        #expect(track.artist == nil)
        #expect(track.album == nil)
        #expect(track.contentKey == nil)
        #expect(track.duration == nil)
        #expect(track.position == nil)
        #expect(track.positionUpdatedAtUnix == nil)
        #expect(track.artwork == .absent)
    }

    @Test(arguments: ["playing", "paused", "buffering", "stopped", "indeterminate"])
    func playbackStatesAreTheirRawValues(_ playback: String) throws {
        let snapshot = try decode(#"{"player": {"name": "K", "playback": "\#(playback)", "features": 0}}"#)
        #expect(snapshot.player.playback.rawValue == playback)
    }

    /// The same normalization the mapper applies, so a server cannot produce a snapshot the app
    /// would never have built.
    @Test func decodedValuesAreNormalized() throws {
        let snapshot = try decode(#"""
        {"player": {"name": "K", "deviceClass": "", "playback": "playing", "volume": 3, "features": 4194303},
         "track": {"title": "Song", "artist": "", "duration": 10, "position": 25,
                   "positionUpdatedAtUnix": 5, "artwork": {"state": "deferred"}}}
        """#)
        #expect(snapshot.player.deviceClass == nil)
        #expect(snapshot.player.volume == 1)
        #expect(snapshot.player.features.rawValue == 20535)
        #expect(snapshot.track?.artist == nil)
        #expect(snapshot.track?.position == 10)

        let negative = try decode(#"""
        {"player": {"name": "K", "playback": "playing", "volume": -1, "features": 0},
         "track": {"title": "Song", "duration": 0, "position": -3, "artwork": {"state": "absent"}}}
        """#)
        #expect(negative.player.volume == 0)
        #expect(negative.track?.duration == nil)
        #expect(negative.track?.position == 0)

        let timestampAlone = try decode(#"""
        {"player": {"name": "K", "playback": "playing", "features": 0},
         "track": {"title": "Song", "positionUpdatedAtUnix": 5, "artwork": {"state": "absent"}}}
        """#)
        #expect(timestampAlone.track?.positionUpdatedAtUnix == nil)
    }

    @Test(arguments: [
        // A player needs a non-empty name, a known playback state and a non-negative integer bitset.
        #"{"player": {"playback": "playing", "features": 0}}"#,
        #"{"player": {"name": "", "playback": "playing", "features": 0}}"#,
        #"{"player": {"name": "K", "playback": "on", "features": 0}}"#,
        #"{"player": {"name": "K", "playback": "playing"}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": -1}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 1.5}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": "1"}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": true}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0, "volume": "0.5"}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0, "volume": true}}"#,
        // A track needs a title, artist, album or content key, and an explicit artwork state. Duration,
        // position and artwork are not identity, exactly as for the mapper.
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"duration": 180, "artwork": {"state": "absent"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"position": 4, "positionUpdatedAtUnix": 5, "artwork": {"state": "absent"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"duration": 180, "position": 4, "artwork": {"state": "deferred"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"artwork": {"state": "available", "url": "https://cdn.example.com/c.jpg"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"artwork": {"state": "absent"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"title": ""}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"title": "S"}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"title": "S", "duration": "180", "artwork": {"state": "absent"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"title": "S", "position": false, "artwork": {"state": "absent"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"title": "S", "positionUpdatedAtUnix": "2026-09-06T12:00:00Z", "artwork": {"state": "absent"}}}"#,
        // A content key is a lowercase digest; a raw content id does not fit in it.
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"contentKey": "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", "artwork": {"state": "absent"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"contentKey": "spotify:track:4uLU6hMCjMI75M1A2tKUQC", "artwork": {"state": "absent"}}}"#,
        #"{"player": {"name": "K", "playback": "playing", "features": 0}, "track": {"contentKey": "https://media.local/stream?api_key=secret", "artwork": {"state": "absent"}}}"#,
        // No player at all.
        #"{"track": {"title": "S", "artwork": {"state": "absent"}}}"#,
        "{}",
    ])
    func malformedSnapshotsDoNotDecode(_ json: String) {
        #expect(throws: DecodingError.self) {
            try decode(json)
        }
    }

    // MARK: - Encoding what a server must reproduce

    /// The exact JSON for an entity, written out literally: key names, which keys are omitted, the
    /// feature bitset as an integer, the timestamp as Unix seconds and the content id as its digest.
    @Test func encodingProducesTheDocumentedShape() throws {
        let snapshot = try RemoteMediaFixtures.report("playing", #"""
        {
            "friendly_name": "Living room",
            "device_class": "speaker",
            "media_title": "Song",
            "media_artist": "Artist",
            "media_album_name": "Album",
            "media_content_id": "abc",
            "media_duration": 180,
            "media_position": 42.5,
            "media_position_updated_at": "2026-09-06T12:00:00.25+00:00",
            "entity_picture": "/api/media_player_proxy/media_player.living_room?token=secret&cache=1",
            "volume_level": 0.5,
            "supported_features": 16387
        }
        """#)
        let expected = try RemoteMediaFixtures.attributes(#"""
        {
            "player": {
                "name": "Living room",
                "deviceClass": "speaker",
                "playback": "playing",
                "volume": 0.5,
                "features": 16387
            },
            "track": {
                "title": "Song",
                "artist": "Artist",
                "album": "Album",
                "contentKey": "\#(Self.digest)",
                "duration": 180,
                "position": 42.5,
                "positionUpdatedAtUnix": 1788696000.25,
                "artwork": {"state": "deferred"}
            }
        }
        """#)
        let encoded = try RemoteMediaFixtures.jsonObject(snapshot)
        #expect(RemoteMediaFixtures.isEqual(encoded, expected))

        let player = try #require(encoded["player"] as? [String: Any])
        let features = try #require(player["features"] as? NSNumber)
        let encoding = String(cString: features.objCType)
        #expect(encoding != "d" && encoding != "f")
    }

    @Test func encodingOmitsWhatIsMissing() throws {
        let snapshot = try RemoteMediaFixtures.report("idle", #"{"friendly_name": "Kitchen"}"#)
        let encoded = try RemoteMediaFixtures.jsonObject(snapshot)
        let expected: [String: Any] = ["player": ["name": "Kitchen", "playback": "stopped", "features": 0]]
        #expect(RemoteMediaFixtures.isEqual(encoded, expected))
    }

    @Test(arguments: [
        (#"{"media_title": "S"}"#, ["state": "absent"]),
        (#"{"media_title": "S", "entity_picture": "/api/media_player_proxy/x?token=t"}"#, ["state": "deferred"]),
        (#"{"media_title": "S", "entity_picture": "https://cdn.example.com/c.jpg"}"#, ["state": "deferred"]),
    ])
    func artworkStatesEncodeExplicitly(_ attributes: String, _ expected: [String: String]) throws {
        let encoded = try RemoteMediaFixtures.jsonObject(RemoteMediaFixtures.report("playing", attributes))
        let track = try #require(encoded["track"] as? [String: Any])
        let artwork = try #require(track["artwork"] as? [String: Any])
        #expect(RemoteMediaFixtures.isEqual(artwork, expected))
    }

    // MARK: - Nothing private on the wire

    /// Every attribute an entity might carry that must never leave the server, at once.
    private static let sensitiveAttributes = #"""
    {
        "friendly_name": "Living room",
        "media_title": "Song",
        "media_content_id": "https://alice:hunter2@media.home.lan:8096/Audio/42/stream?api_key=SENSITIVE-1",
        "media_duration": 180,
        "media_position": 1,
        "media_position_updated_at": "2026-09-06T12:00:00+00:00",
        "entity_picture": "/api/media_player_proxy/media_player.living_room?token=SENSITIVE-2&cache=9f",
        "entity_picture_local": "/api/media_player_proxy/media_player.living_room?token=SENSITIVE-3",
        "media_image_url": "http://192.168.1.20:32400/photo?X-Plex-Token=SENSITIVE-4",
        "access_token": "SENSITIVE-5",
        "webhook_id": "SENSITIVE-6",
        "webhook_url": "https://hooks.nabu.casa/SENSITIVE-7",
        "push_token": "SENSITIVE-8",
        "supported_features": 16387
    }
    """#

    /// The paths a snapshot can contain, and what each may hold. This is the whole wire contract;
    /// a field outside it fails this test.
    private static let schema: [String: (Any) -> Bool] = [
        "player.name": { $0 is String },
        "player.deviceClass": { $0 is String },
        "player.playback": { value in (value as? String).flatMap(RemoteMediaPlaybackState.init(rawValue:)) != nil },
        "player.volume": { $0 is NSNumber },
        "player.features": { $0 is NSNumber },
        "track.title": { $0 is String },
        "track.artist": { $0 is String },
        "track.album": { $0 is String },
        "track.contentKey": RemoteMediaSnapshotWireTests.isDigest,
        "track.duration": { $0 is NSNumber },
        "track.position": { $0 is NSNumber },
        "track.positionUpdatedAtUnix": { $0 is NSNumber },
        "track.artwork.state": { ["absent", "deferred", "available"].contains($0 as? String) },
        "track.artwork.cacheKey": RemoteMediaSnapshotWireTests.isDigest,
        "track.artwork.url": { value in (value as? String).map { $0.hasPrefix("https://") } ?? false },
    ]

    private static func isDigest(_ value: Any) -> Bool {
        guard let text = value as? String else { return false }
        return text.count == 64 && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Every leaf of a JSON object, by dotted path.
    private static func leaves(of object: [String: Any], prefix: String = "") -> [(path: String, value: Any)] {
        object.flatMap { key, value -> [(path: String, value: Any)] in
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any] { return leaves(of: nested, prefix: path) }
            return [(path, value)]
        }
    }

    /// The structure, not a search for known secrets, is what keeps them out: every value in the
    /// encoded snapshot sits at a path the schema allows and has the shape that path allows, and the
    /// only free-text paths are the display names and metadata the entity already shows.
    @Test func theWirePayloadHoldsOnlyTheSchema() throws {
        let mapped = try RemoteMediaFixtures.mapped("playing", Self.sensitiveAttributes)
        let encoded = try RemoteMediaFixtures.jsonObject(mapped.snapshot)
        let leaves = Self.leaves(of: encoded)
        #expect(!leaves.isEmpty)
        for leaf in leaves {
            let validator = try #require(Self.schema[leaf.path], "\(leaf.path) is not part of the wire contract")
            #expect(validator(leaf.value), "\(leaf.path) holds \(leaf.value)")
        }
        let freeText = leaves.filter { ["player.name", "track.title"].contains($0.path) }.map { $0.value as? String }
        #expect(Set(freeText) == ["Living room", "Song"])
    }

    /// The same payload, checked for the specific values that must not appear in it, as a second line
    /// of defense behind the schema: no credential or token, no webhook, no signed Home Assistant
    /// image path or other address, and no raw content id. With a `friendly_name` present, the entity
    /// id does not appear either.
    @Test func noCredentialRoutingValueOrRawContentIdReachesTheWire() throws {
        let mapped = try RemoteMediaFixtures.mapped("playing", Self.sensitiveAttributes)
        let json = try String(decoding: JSONEncoder().encode(mapped.snapshot), as: UTF8.self)
        for forbidden in [
            "SENSITIVE", "token", "api_key", "hunter2", "alice", "media.home.lan", "192.168.", "/api/",
            "media_player_proxy", "media_player.living_room", "webhook", "nabu.casa", "stream",
        ] {
            #expect(!json.contains(forbidden), "The wire payload contains \(forbidden)")
        }
        // The proxied picture is still available on the device, which is where it belongs.
        #expect(mapped.artworkSource?.contains("SENSITIVE-2") == true)
    }

    /// Without a `friendly_name`, the entity id is the player's display name, as it is in Home
    /// Assistant. That is the only place it can appear: there is no field that carries it for routing.
    @Test func theEntityIdAppearsOnlyAsTheDisplayNameFallback() throws {
        var attributes = try RemoteMediaFixtures.attributes(Self.sensitiveAttributes)
        attributes["friendly_name"] = nil
        let entityId = try RemoteMediaFixtures.entityId
        let snapshot = RemoteMediaSnapshotMapper.map(entityId: entityId, state: "playing", attributes: attributes)
            .snapshot
        let leaves = try Self.leaves(of: RemoteMediaFixtures.jsonObject(snapshot))
        let carryingEntityId = leaves.filter { leaf in
            (leaf.value as? String)?.contains(entityId.rawValue) == true
        }
        #expect(carryingEntityId.map(\.path) == ["player.name"])
    }

    // MARK: - Content keys

    /// Each expected digest is `hashlib.sha256(value.encode()).hexdigest()`, computed in Python. The
    /// two spellings of "Café" differ only in Unicode normalization, and so do their digests: neither
    /// side normalizes, so both must hash the bytes exactly as Home Assistant reported them.
    @Test(arguments: [
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (
            "spotify:track:\u{DC}n\u{EF}c\u{F8}d\u{E9} \u{1F3B5} \u{66F2}",
            "c25b6369b2ab6c4d54375e7faea0a673f9923f6238b8f12da59c23e85918c27a"
        ),
        ("Caf\u{E9}", "73473dcc12b763085904a5279d048c4d5b3b008c46f1f32443b99de04aa83a14"),
        ("Cafe\u{301}", "c42cc7a1ca08364b6fd859fa50d2454730a8236290a423373cc630da77c6d711"),
    ])
    func contentKeysMatchPython(_ contentId: String, _ digest: String) throws {
        let entityId = try RemoteMediaFixtures.entityId
        let track = RemoteMediaSnapshotMapper.map(
            entityId: entityId,
            state: "playing",
            attributes: ["media_content_id": contentId]
        ).snapshot.track
        #expect(track?.contentKey?.hexString == digest)
    }
}
