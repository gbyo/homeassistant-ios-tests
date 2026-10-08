import Foundation
import RemoteMediaCore
import Testing

/// `media_position_updated_at` as Home Assistant writes it, read through the mapper.
struct RemoteMediaTimestampTests {
    /// `datetime.fromisoformat("2026-09-06T12:00:00+00:00").timestamp()`.
    static let noon: TimeInterval = 1_788_696_000

    private func positionUpdatedAt(_ timestamp: Any) throws -> TimeInterval? {
        let entityId = try RemoteMediaFixtures.entityId
        let track = RemoteMediaSnapshotMapper.map(
            serverId: "server-1",
            entityId: entityId,
            state: "playing",
            attributes: [
                "media_title": "Song", "media_position": 1, "media_position_updated_at": timestamp,
            ]
        ).snapshot.track
        return track?.positionUpdatedAtUnix
    }

    static let accepted: [(String, TimeInterval)] = [
        // `isoformat()` of an aware UTC datetime, with and without microseconds.
        ("2026-09-06T12:00:00+00:00", RemoteMediaTimestampTests.noon),
        ("2026-09-06T12:00:00.123456+00:00", RemoteMediaTimestampTests.noon + 0.123456),
        // `str()` of the same, which is what a template renders.
        ("2026-09-06 12:00:00+00:00", RemoteMediaTimestampTests.noon),
        ("2026-09-06 12:00:00.123456+00:00", RemoteMediaTimestampTests.noon + 0.123456),
        ("2026-09-06T12:00:00Z", RemoteMediaTimestampTests.noon),
        ("2026-09-06T12:00:00.5Z", RemoteMediaTimestampTests.noon + 0.5),
        ("2026-09-06T12:00:00.123Z", RemoteMediaTimestampTests.noon + 0.123),
        ("2026-09-06T12:00:00.123456789Z", RemoteMediaTimestampTests.noon + 0.123456789),
        // Offsets other than UTC name the same instant.
        ("2026-09-06T08:00:00-04:00", RemoteMediaTimestampTests.noon),
        ("2026-09-06T17:30:00+05:30", RemoteMediaTimestampTests.noon),
        ("2024-02-29T00:00:00+00:00", 1_709_164_800),
        // Divisible by 400, so a leap year.
        ("2000-02-29T00:00:00+00:00", 951_782_400),
        ("1970-01-01T00:00:00Z", 0),
        // The extremes of the four-digit year, from Python's `datetime(…).timestamp()`.
        ("0001-01-01T00:00:00+00:00", -62_135_596_800),
        ("9999-12-31T23:59:59+00:00", 253_402_300_799),
        ("9999-12-31T23:59:59-23:59", 253_402_300_799 + 86340),
    ]

    @Test(arguments: accepted)
    func homeAssistantTimestampsBecomeUnixSeconds(_ timestamp: String, _ expected: TimeInterval) throws {
        let updatedAt = try positionUpdatedAt(timestamp)
        let parsed = try #require(updatedAt)
        #expect(abs(parsed - expected) < 0.000_001)
    }

    @Test(arguments: [
        "", "not a date", "2026-09-06", "12:00:00",
        // No offset: the instant would depend on whoever reads it.
        "2026-09-06T12:00:00", "2026-09-06T12:00:00.123456",
        // Offsets in a form `isoformat()` never writes.
        "2026-09-06T12:00:00+0000", "2026-09-06T12:00:00+00", "2026-09-06T12:00:00+00:00:00",
        "2026-09-06T12:00:00+24:00", "2026-09-06T12:00:00+00:60",
        // Missing or malformed pieces.
        "2026-09-06T12:00Z", "2026-9-6T12:00:00Z", "2026-09-06T12:00:00.Z", "2026-09-06T12:00:00.1234567890Z",
        "2026-09-06t12:00:00z", "2026-09-06_12:00:00Z", "2026/09/06T12:00:00Z",
        // Out of range.
        "2026-13-01T00:00:00Z", "2026-00-01T00:00:00Z", "2026-02-29T00:00:00Z", "2026-09-31T00:00:00Z",
        // Divisible by 100 but not 400, so not leap years.
        "1900-02-29T00:00:00Z", "2100-02-29T00:00:00Z",
        "2026-09-06T24:00:00Z", "2026-09-06T12:60:00Z", "2026-09-06T12:00:60Z", "0000-01-01T00:00:00Z",
        // Surrounding or lookalike characters.
        " 2026-09-06T12:00:00Z", "2026-09-06T12:00:00Z ", "2026-09-06T12:00:00Z\n",
        "\u{FF12}026-09-06T12:00:00Z",
    ])
    func anythingElseIsNoTimestamp(_ timestamp: String) throws {
        let updatedAt = try positionUpdatedAt(timestamp)
        #expect(updatedAt == nil)
    }

    @Test func aNonStringIsNoTimestamp() throws {
        let number = try positionUpdatedAt(RemoteMediaTimestampTests.noon)
        let date = try positionUpdatedAt(Date(timeIntervalSince1970: RemoteMediaTimestampTests.noon))
        #expect(number == nil)
        #expect(date == nil)
    }

    /// The app and the extension map from concurrent tasks; nothing about parsing is shared.
    @Test func parsingIsSafeFromConcurrentCallers() async throws {
        let entityId = try RemoteMediaFixtures.entityId
        let results = await withTaskGroup(of: TimeInterval?.self) { group in
            for index in 0 ..< 500 {
                group.addTask {
                    let timestamp = index.isMultiple(of: 2)
                        ? "2026-09-06T12:00:00.123456+00:00"
                        : "2026-09-06 08:00:00.123456-04:00"
                    return RemoteMediaSnapshotMapper.map(
                        serverId: "server-1",
                        entityId: entityId,
                        state: "playing",
                        attributes: [
                            "media_title": "Song", "media_position": 1, "media_position_updated_at": timestamp,
                        ]
                    ).snapshot.track?.positionUpdatedAtUnix
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == 500)
        #expect(Set(results).count == 1)
        let parsed = try #require(results.first ?? nil)
        #expect(abs(parsed - (Self.noon + 0.123456)) < 0.000_001)
    }
}
