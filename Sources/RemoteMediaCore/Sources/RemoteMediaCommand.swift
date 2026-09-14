import Foundation

public enum RemoteMediaCommand: String, CaseIterable, Sendable {
    case play, pause, togglePlayPause, stop, previous, next, seek, volume

    /// The `media_player` service this control calls. `RemoteMediaServiceCall` turns it into the
    /// payload that is actually sent.
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

    /// `value` as this command will actually be sent, clamped to the range the service accepts.
    ///
    /// Defined once because everything that reasons about the request has to agree on it: whoever
    /// sends the call and whoever later checks whether the player did what was asked. Clamping in
    /// only one of those places leaves an out-of-range request that can never be satisfied.
    public func clamped(_ value: Double) -> Double {
        switch self {
        case .seek: return max(0, value)
        case .volume: return min(1, max(0, value))
        case .play, .pause, .togglePlayPause, .stop, .previous, .next: return value
        }
    }
}
