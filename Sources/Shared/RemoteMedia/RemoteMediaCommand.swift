import Foundation

public enum RemoteMediaCommand: String, CaseIterable, Sendable {
    case play, pause, togglePlayPause, stop, previous, next, seek, volume

    public var service: String {
        switch self {
        case .play: return "media_play"
        case .pause: return "media_pause"
        case .togglePlayPause: return "media_play_pause"
        case .stop: return "media_stop"
        case .previous: return "media_previous_track"
        case .next: return "media_next_track"
        case .seek: return "media_seek"
        case .volume: return "volume_set"
        }
    }

    public func serviceData(entityId: String, value: Double? = nil) throws -> [String: Any] {
        var data: [String: Any] = ["entity_id": entityId]
        switch self {
        case .seek, .volume:
            guard let value, value.isFinite else { throw RemoteMediaError.invalidCommand }
            data[self == .seek ? "seek_position" : "volume_level"] = self == .seek
                ? max(0, value) : min(1, max(0, value))
        default: break
        }
        return data
    }
}
