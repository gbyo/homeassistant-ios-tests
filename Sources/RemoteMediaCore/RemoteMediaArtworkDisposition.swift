import Foundation

/// Whether a snapshot supplies artwork, explicitly clears it, or is waiting for preparation.
public enum RemoteMediaArtworkDisposition: String, Codable, Equatable, Sendable {
    case deferred
    case available
    case absent
}
