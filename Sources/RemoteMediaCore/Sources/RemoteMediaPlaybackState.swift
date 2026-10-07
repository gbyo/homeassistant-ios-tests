import Foundation

/// What the followed player is doing, independent of how its integration spells it.
///
/// Integrations differ in how they describe the same thing: an Echo answering Pause can pass
/// through `idle` on its way from `playing` to `paused`. Collapsing the spellings here keeps that
/// variation out of everything downstream. The raw value is the wire representation.
public enum RemoteMediaPlaybackState: String, Sendable, Codable {
    case playing
    case paused
    case buffering
    /// `idle`, `on`, `off` or `standby`: the player is reachable and not playing anything.
    case stopped
    /// `unavailable`, `unknown`, or a state this feature does not recognize: the integration is not
    /// saying, which is not the same as having stopped.
    case indeterminate

    init(homeAssistantState state: String) {
        switch state {
        case "playing": self = .playing
        case "paused": self = .paused
        case "buffering": self = .buffering
        case "idle", "on", "off", "standby": self = .stopped
        default: self = .indeterminate
        }
    }
}
