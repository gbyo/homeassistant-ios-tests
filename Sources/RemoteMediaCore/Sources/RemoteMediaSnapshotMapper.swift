import Foundation

/// Turns one `media_player` entity's state into a `RemoteMediaEntityState`.
///
/// The one mapping, so every view of a player agrees, and simple enough for a server producing
/// snapshots itself to reproduce:
///
/// - A **string** attribute is present only when it is non-empty.
/// - A **number** is a finite JSON number. Booleans are not numbers (Foundation bridges them through
///   `NSNumber`), and neither are numeric strings.
/// - `supported_features` must be an integer, is masked as `RemoteMediaFeatures` describes, and
///   means no features when negative.
/// - `friendly_name` falls back to the entity id.
/// - `media_content_id` becomes a `RemoteMediaDigest`; the id itself is never carried.
/// - `media_position_updated_at` is read as `RemoteMediaTimestamp` describes.
/// - `entity_picture` makes the artwork `deferred`, or `absent` when missing. The picture itself stays
///   out of the snapshot, even when it looks public, and is returned as
///   `RemoteMediaEntityState.artworkSource` for the app to fetch over its own connection.
///
/// Clamping, empty values and the like are the normalization `RemoteMediaPlayer` and
/// `RemoteMediaTrack` apply to everything they are given.
public enum RemoteMediaSnapshotMapper {
    /// - Parameter serverId: A stable local identifier of the server the entity belongs to, such as the
    ///   app's server identifier, passed unchanged on every report for that server. It is not read from
    ///   the entity and never reaches a snapshot; it only keeps one server's artwork from being taken
    ///   for another's, since `entity_picture` is usually a path relative to its server.
    public static func map(
        serverId: String,
        entityId: RemoteMediaEntityId,
        state: String,
        attributes: [String: Any]
    ) -> RemoteMediaEntityState {
        let artworkReference = string(attributes["entity_picture"])
        let player = RemoteMediaPlayer(
            name: string(attributes["friendly_name"]) ?? entityId.rawValue,
            deviceClass: string(attributes["device_class"]),
            playback: RemoteMediaPlaybackState(homeAssistantState: state),
            volume: number(attributes["volume_level"]),
            features: integer(attributes["supported_features"])
                .map(RemoteMediaFeatures.init(supportedFeatures:)) ?? []
        )
        let track = RemoteMediaTrack(
            title: string(attributes["media_title"]),
            artist: string(attributes["media_artist"]),
            album: string(attributes["media_album_name"]),
            contentKey: string(attributes["media_content_id"]).map(RemoteMediaDigest.init(hashing:)),
            duration: number(attributes["media_duration"]),
            position: number(attributes["media_position"]),
            positionUpdatedAtUnix: string(attributes["media_position_updated_at"])
                .flatMap(RemoteMediaTimestamp.unixSeconds(from:)),
            artwork: artworkReference == nil ? .absent : .deferred
        )
        return RemoteMediaEntityState(
            snapshot: RemoteMediaSnapshot(player: player, track: track),
            artworkReference: artworkReference,
            artworkScope: RemoteMediaDigest(hashingFields: [serverId, entityId.rawValue]),
            trackIdentity: track?.identity
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = numericNSNumber(value) else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = numericNSNumber(value) else { return nil }
        let encoding = String(cString: number.objCType)
        // `f` and `d` are the floating-point encodings; `NSDecimalNumber` reports `d` as well.
        return encoding == "f" || encoding == "d" ? nil : number.intValue
    }

    /// `value` as a number, unless it is a boolean.
    ///
    /// JSON booleans and Swift `Bool`s both reach an `[String: Any]` as `NSNumber`s that are happy to
    /// answer `doubleValue` and `intValue`, which is how `supported_features: true` would otherwise
    /// claim the pause feature. They are the `CFBoolean` singletons, which is what tells them apart.
    private static func numericNSNumber(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }
}
