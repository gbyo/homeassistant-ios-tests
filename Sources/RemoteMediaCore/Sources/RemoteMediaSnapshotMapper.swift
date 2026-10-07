import Foundation

/// Turns one `media_player` entity's state into a `RemoteMediaSnapshot`.
///
/// The single mapping, whichever way the attributes arrived: two mappings of the same attributes is
/// how two views of the same player drift apart. A server producing snapshots itself has to apply
/// exactly these rules, so they are kept simple enough to state:
///
/// - A **string** attribute is present only when it is a non-empty string.
/// - A **number** is present only when it is a finite JSON number. `true` and `false` are not numbers,
///   even though Foundation bridges them through `NSNumber`, and neither is a numeric string.
/// - `supported_features` must be an integer — not a boolean, not a float — and is masked as
///   `RemoteMediaFeatures` describes. A negative value means no features.
/// - `friendly_name` falls back to the entity id.
/// - `media_content_id` becomes a `RemoteMediaDigest` and is never carried itself.
/// - `media_position_updated_at` is read as `RemoteMediaTimestamp` describes and written as Unix
///   seconds.
/// - `entity_picture` makes the artwork `deferred` when present and `absent` when missing. The picture
///   itself is never copied into the snapshot, even when it looks public: the app can always fetch it
///   through its own authenticated connection, so the only thing the wire needs to say is whether
///   there is one. It is returned beside the snapshot as `RemoteMediaEntityState.artworkSource`.
///
/// Everything else — clamping, empty values, a timestamp without a position — is the normalization
/// `RemoteMediaPlayer` and `RemoteMediaTrack` apply to every value they are given.
public enum RemoteMediaSnapshotMapper {
    public static func map(
        entityId: RemoteMediaEntityId,
        state: String,
        attributes: [String: Any]
    ) -> RemoteMediaEntityState {
        let artworkSource = string(attributes["entity_picture"])
        let player = RemoteMediaPlayer(
            entityId: entityId,
            friendlyName: string(attributes["friendly_name"]),
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
            artwork: artworkSource == nil ? .absent : .deferred
        )
        return RemoteMediaEntityState(
            snapshot: RemoteMediaSnapshot(player: player, track: track),
            artworkSource: artworkSource
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
