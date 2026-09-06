import Foundation
import HAKit

public enum RemoteMediaSnapshotMapper {
    public static func map(_ entity: HAEntity, serverId: String) -> RemoteMediaSnapshot? {
        guard entity.domain == "media_player" else { return nil }
        let attributes = entity.attributes
        let duration = finite(attributes["media_duration"]).flatMap { $0 > 0 ? $0 : nil }
        let position = finite(attributes["media_position"])
            .map { min(duration ?? .greatestFiniteMagnitude, max(0, $0)) }
        let timestamp = (attributes["media_position_updated_at"] as? String).flatMap { text -> Date? in
            fractionalSecondsFormatter.date(from: text) ?? wholeSecondsFormatter.date(from: text)
        }
        return RemoteMediaSnapshot(
            selection: .init(serverId: serverId, entityId: entity.entityId),
            deviceName: attributes.friendlyName ?? entity.entityId,
            deviceClass: attributes["device_class"] as? String,
            state: entity.state,
            title: attributes["media_title"] as? String,
            artist: attributes["media_artist"] as? String,
            album: attributes["media_album_name"] as? String,
            contentId: attributes["media_content_id"] as? String,
            duration: duration,
            position: position,
            positionUpdatedAt: position == nil ? nil : timestamp,
            artworkPath: attributes["entity_picture"] as? String,
            volume: finite(attributes["volume_level"]).map { min(1, max(0, $0)) },
            isMuted: attributes["is_volume_muted"] as? Bool,
            features: .init(rawValue: max(0, attributes["supported_features"] as? Int ?? 0))
        )
    }

    /// Home Assistant timestamps carry fractional seconds, but not always: `ISO8601DateFormatter`
    /// rejects a string whose precision does not match its options, so both are tried.
    private static let fractionalSecondsFormatter = with(ISO8601DateFormatter()) {
        $0.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    private static let wholeSecondsFormatter = with(ISO8601DateFormatter()) {
        $0.formatOptions = [.withInternetDateTime]
    }

    private static func finite(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
}
