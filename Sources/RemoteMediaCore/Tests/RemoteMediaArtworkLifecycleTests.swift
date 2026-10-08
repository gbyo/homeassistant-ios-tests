import Foundation
import RemoteMediaCore
import Testing

/// A cover's life as the app that prepares covers would live it, written against the public API
/// only: report, reconcile, ask what to show, and attach whatever was prepared.
struct RemoteMediaArtworkLifecycleTests {
    private static let coverA = "/api/media_player_proxy/media_player.living_room?token=secret&cache=a"
    private static let coverB = "/api/media_player_proxy/media_player.living_room?token=secret&cache=b"

    // MARK: - Attaching a prepared cover

    @Test func aPreparedCoverReplacesNothingButTheCover() throws {
        let state = try report("track-1", picture: Self.coverA)
        let source = try #require(state.artworkSource)

        let shown = state.displayedSnapshot(preparedArtworkFrom: source)

        #expect(shown.track?.artwork == .available(.cached(source.cacheKey)))
        #expect(shown.player == state.snapshot.player)
        let before = try #require(state.snapshot.track)
        let after = try #require(shown.track)
        #expect(after.title == before.title)
        #expect(after.artist == before.artist)
        #expect(after.album == before.album)
        #expect(after.contentKey == before.contentKey)
        #expect(after.duration == before.duration)
        #expect(after.position == before.position)
        #expect(after.positionUpdatedAtUnix == before.positionUpdatedAtUnix)
        // Derived, so repeatable, and never remembered by the reconciled state.
        #expect(state.displayedSnapshot(preparedArtworkFrom: source) == shown)
        #expect(state.snapshot.track?.artwork == .deferred)
    }

    @Test func aCoverPreparedForAnotherSourceOrForNoCoverAttachesNothing() throws {
        let state = try report("track-1", picture: Self.coverA)
        let bare = try report("track-1", picture: nil)
        let other = try #require(report("track-1", picture: Self.coverB).artworkSource)
        let source = try #require(state.artworkSource)

        #expect(state.displayedSnapshot(preparedArtworkFrom: other) == state.snapshot)
        #expect(bare.displayedSnapshot(preparedArtworkFrom: source) == bare.snapshot)
    }

    // MARK: - Reconciling

    /// Integrations leave attributes out while they refresh, and Home Assistant cannot say a picture
    /// was withdrawn, so a report without one keeps the cover of the same track, source and all.
    @Test func aReportThatLeavesOutThePictureKeepsTheCover() throws {
        let first = try report("track-1", picture: Self.coverA)
        let source = try #require(first.artworkSource)

        let next = try reduce(first, report("track-1", picture: nil))

        #expect(next.artworkSource == source)
        #expect(
            next.displayedSnapshot(preparedArtworkFrom: source).track?.artwork == .available(.cached(source.cacheKey))
        )
    }

    @Test func aCoverArrivingAfterTheTrackIsTheSameTrackGainingACover() throws {
        let next = try reduce(report("track-1", picture: nil), report("track-1", picture: Self.coverA))
        #expect(next.snapshot.track?.artwork == .deferred)
        #expect(next.artworkSource?.reference == Self.coverA)
    }

    /// The track is unchanged but Home Assistant now serves a different picture: only the source says so.
    @Test func aNewPictureForTheSameTrackInvalidatesThePreparedCover() throws {
        let first = try report("track-1", picture: Self.coverA)
        let sourceA = try #require(first.artworkSource)

        let next = try reduce(first, report("track-1", picture: Self.coverB))
        let sourceB = try #require(next.artworkSource)

        #expect(sourceB != sourceA)
        #expect(sourceB.cacheKey != sourceA.cacheKey)
        #expect(next.displayedSnapshot(preparedArtworkFrom: sourceA).track?.artwork == .deferred)
        #expect(
            next.displayedSnapshot(preparedArtworkFrom: sourceB).track?.artwork == .available(.cached(sourceB.cacheKey))
        )
        // A later report without a picture keeps the new one, not the old one.
        let later = try reduce(next, report("track-1", picture: nil))
        #expect(later.artworkSource == sourceB)
    }

    /// Song A and Song B report the same address. The reducer rightly sees a new track, so a cover
    /// prepared for Song A must not appear on Song B, which needs a preparation of its own.
    @Test func theSamePictureOnANewTrackNeedsFreshPreparation() throws {
        let first = try report("track-1", picture: Self.coverA)
        let sourceA = try #require(first.artworkSource)

        let next = try reduce(first, report("track-2", picture: Self.coverA))
        let sourceB = try #require(next.artworkSource)

        #expect(sourceB.reference == sourceA.reference)
        #expect(sourceB != sourceA)
        #expect(sourceB.cacheKey != sourceA.cacheKey)
        #expect(next.displayedSnapshot(preparedArtworkFrom: sourceA).track?.artwork == .deferred)
        #expect(
            next.displayedSnapshot(preparedArtworkFrom: sourceB).track?.artwork == .available(.cached(sourceB.cacheKey))
        )
    }

    @Test func aNewTrackWithoutAPictureHasNoCover() throws {
        let first = try report("track-1", picture: Self.coverA)
        let sourceA = try #require(first.artworkSource)

        let next = try reduce(first, report("track-2", picture: nil))

        #expect(next.snapshot.track?.artwork == .absent)
        #expect(next.artworkSource == nil)
        #expect(next.displayedSnapshot(preparedArtworkFrom: sourceA) == next.snapshot)
    }

    /// An entity that reports nothing keeps showing the last track, and the cover goes with it.
    @Test func aReportWithNoTrackKeepsTheCoverOfTheTrackItKeeps() throws {
        let first = try report("track-1", picture: Self.coverA)
        let next = try reduce(first, RemoteMediaFixtures.mapped("idle"))
        #expect(next.snapshot.track?.title == "Song")
        #expect(next.artworkSource == first.artworkSource)
    }

    // MARK: - Identity: one track, one player

    /// Repeated, incomplete and relaunched reports of the same track at the same address leave the source
    /// exactly as it was, which is how the app knows there is nothing new to prepare.
    @Test func reportsOfTheSameTrackNeverAskForNewPreparation() throws {
        let sparse = try report("track-1", picture: Self.coverA, partial: true)
        let source = try #require(sparse.artworkSource)
        let titleOnly = try RemoteMediaFixtures.mapped(
            "paused", #"{"media_title": "Song", "entity_picture": "\#(Self.coverA)"}"#
        )

        var state = sparse
        for incoming in try [
            report("track-1", picture: Self.coverA),
            sparse,
            titleOnly,
            report("track-1", picture: nil),
        ] {
            state = reduce(state, incoming)
            #expect(state.artworkSource == source)
            #expect(
                state.displayedSnapshot(preparedArtworkFrom: source).track?
                    .artwork == .available(.cached(source.cacheKey))
            )
        }
        // A fresh mapping, as after a relaunch, names the same source and so the same cached file.
        let relaunched = try #require(report("track-1", picture: Self.coverA, partial: true).artworkSource)
        #expect(relaunched == source)
        #expect(relaunched.cacheKey == source.cacheKey)
    }

    /// Two servers, or two entities, can report the same path and track and serve different images.
    @Test(arguments: [("server-cabin", "media_player.living_room"), ("server-1", "media_player.kitchen")])
    func theSameTrackAndPathOnAnotherPlayerIsADifferentCover(server: String, entity: String) throws {
        let home = try report("track-1", picture: Self.coverA)
        let other = try report("track-1", picture: Self.coverA, server: server, entity: entity)
        let homeSource = try #require(home.artworkSource)
        let otherSource = try #require(other.artworkSource)

        #expect(homeSource.reference == otherSource.reference)
        #expect(homeSource != otherSource)
        #expect(homeSource.cacheKey != otherSource.cacheKey)
        #expect(other.displayedSnapshot(preparedArtworkFrom: homeSource).track?.artwork == .deferred)
    }

    /// Player, track and picture each separate sources, across a track change and back (A → B → A) on
    /// two players that never mix.
    @Test func trackChangesAndReturnsStayWithinTheirOwnPlayer() throws {
        var home = try report("track-1", picture: Self.coverA, server: "server-home")
        var cabin = try report("track-1", picture: Self.coverA, server: "server-cabin")
        let homeA = try #require(home.artworkSource)
        let cabinA = try #require(cabin.artworkSource)

        home = try reduce(home, report("track-2", picture: Self.coverA, server: "server-home"))
        cabin = try reduce(cabin, report("track-2", picture: Self.coverA, server: "server-cabin"))
        let sources = try [homeA, #require(home.artworkSource), cabinA, #require(cabin.artworkSource)]
        #expect(Set(sources).count == 4)
        #expect(Set(sources.map(\.cacheKey)).count == 4)

        home = try reduce(home, report("track-1", picture: Self.coverA, server: "server-home"))
        #expect(home.artworkSource == homeA)
        #expect(home.displayedSnapshot(preparedArtworkFrom: cabinA).track?.artwork == .deferred)
    }

    /// Fields are length-prefixed, so values that only differ in where one ends and the next begins
    /// cannot collide.
    @Test func serverIdentifiersThatRunTogetherStayDistinct() throws {
        let servers = ["a", "a:", ":a", "1:a", "", "a1", "11:a"]
        let keys = try servers
            .map { try #require(report("track-1", picture: Self.coverA, server: $0).artworkSource).cacheKey }
        #expect(Set(keys).count == servers.count)
    }

    // MARK: - Staying on the device

    /// Neither the picture's address, nor the server, nor the entity is printed or put in a snapshot;
    /// the cache key that is, is an opaque digest.
    @Test func nothingSensitiveIsPrintedOrExposed() throws {
        let state = try report("track-1", picture: Self.coverA, server: "SERVER-IDENTIFIER-123")
        let source = try #require(state.artworkSource)
        let shown = state.displayedSnapshot(preparedArtworkFrom: source)

        let texts = [
            String(describing: source), String(reflecting: source), String(describing: state),
            String(reflecting: state), String(describing: shown),
        ]
        for text in texts {
            for secret in ["secret", "media_player_proxy", "SERVER-IDENTIFIER-123"] {
                #expect(!text.contains(secret), "\(text) contains \(secret)")
            }
        }
        let key = source.cacheKey.hexString
        #expect(key.count == 64)
        #expect(key.allSatisfy { "0123456789abcdef".contains($0) })
    }

    // MARK: - Helpers

    private func reduce(
        _ previous: RemoteMediaEntityState,
        _ incoming: RemoteMediaEntityState
    ) -> RemoteMediaEntityState {
        RemoteMediaSnapshotReducer.reduce(previous: previous, incoming: incoming)
    }

    private func report(
        _ contentId: String,
        picture: String?,
        server: String = "server-1",
        entity: String = "media_player.living_room",
        partial: Bool = false
    ) throws -> RemoteMediaEntityState {
        let entityId = try #require(RemoteMediaEntityId(entity))
        var attributes: [String: Any] = ["media_content_id": contentId]
        if !partial {
            attributes["media_title"] = contentId == "track-2" ? "Next" : "Song"
            attributes["media_artist"] = "Artist"
            attributes["media_album_name"] = "Album"
            attributes["media_duration"] = 200
            attributes["media_position"] = 10
            attributes["media_position_updated_at"] = "2026-09-06T12:00:00+00:00"
        }
        attributes["entity_picture"] = picture
        return RemoteMediaSnapshotMapper.map(
            serverId: server, entityId: entityId, state: "playing", attributes: attributes
        )
    }
}
