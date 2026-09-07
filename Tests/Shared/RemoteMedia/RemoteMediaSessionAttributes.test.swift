#if !targetEnvironment(macCatalyst)
import Foundation
@testable import Shared
import Testing

/// Type-level behaviour of the attributes. The encoded JSON is a separate, stricter contract —
/// see `RemoteMediaWireContractTests`.
struct RemoteMediaSessionAttributesTests {
    private func snapshot(entityId: String = "media_player.speaker") -> RemoteMediaSnapshot {
        .init(
            selection: .init(serverId: "home", entityId: entityId),
            deviceName: "Speaker",
            deviceClass: nil,
            state: "playing",
            title: "Title",
            artist: nil,
            album: nil,
            contentId: "content",
            duration: nil,
            position: nil,
            positionUpdatedAtUnix: nil,
            artwork: nil,
            volume: nil,
            isMuted: nil,
            features: []
        )
    }

    @Test func theIdentifierMatchesTheFollowedSelection() throws {
        guard #available(iOS 27.0, *) else { return }
        let snapshot = snapshot()
        #expect(RemoteMediaSessionAttributes(snapshot: snapshot).id == snapshot.selection.id)
    }

    @Test func attributesRoundTrip() throws {
        guard #available(iOS 27.0, *) else { return }
        let original = RemoteMediaSessionAttributes(snapshot: snapshot(), generation: "lifetime")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteMediaSessionAttributes.self, from: encoded)
        #expect(decoded.id == original.id)
        #expect(decoded.generation == "lifetime")
        #expect(decoded.snapshot == original.snapshot)
    }
}
#endif
