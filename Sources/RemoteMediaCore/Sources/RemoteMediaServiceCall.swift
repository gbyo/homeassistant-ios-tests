import Foundation

/// The `media_player` service call one Now Playing control stands for.
///
/// Built from the command and its value alone. Which controls exist is `RemoteMediaFeatures`'
/// business, decided from the entity's state before a control is ever pressed, so nothing here
/// needs to read entity state back to build a payload.
public struct RemoteMediaServiceCall: Equatable, Sendable {
    public let domain = "media_player"
    public let service: String
    public let serviceData: [String: RemoteMediaServiceValue]

    public init(command: RemoteMediaCommand, entityId: String, value: Double? = nil) throws {
        self.service = command.service
        var data: [String: RemoteMediaServiceValue] = ["entity_id": .string(entityId)]
        switch command {
        case .seek:
            guard let value, value.isFinite else { throw RemoteMediaError.invalidCommand }
            data["seek_position"] = .number(command.clamped(value))
        case .volume:
            guard let value, value.isFinite else { throw RemoteMediaError.invalidCommand }
            data["volume_level"] = .number(command.clamped(value))
        case .play, .pause, .togglePlayPause, .stop, .previous, .next:
            break
        }
        self.serviceData = data
    }

    /// The `call_service` payload's `data` value, in `mobile_app`'s shape.
    public var webhookData: [String: Any] {
        [
            "domain": domain,
            "service": service,
            "service_data": serviceData.mapValues(\.jsonValue),
        ]
    }
}

/// The value types a `media_player` service call needs, kept concrete so payloads stay `Equatable`
/// and testable rather than being `[String: Any]` all the way down.
public enum RemoteMediaServiceValue: Equatable, Sendable {
    case string(String)
    case number(Double)

    public var jsonValue: Any {
        switch self {
        case let .string(value): return value
        case let .number(value): return value
        }
    }
}
