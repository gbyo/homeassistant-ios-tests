import Foundation

/// Playback data without any dependency on Apple's session framework or credentials.
public struct RemoteMediaSnapshot: Codable, Equatable, Sendable {
    public let selection: RemoteMediaSelection
    public let deviceName: String
    public let deviceClass: String?
    public let state: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let contentId: String?
    public let duration: TimeInterval?
    public let position: TimeInterval?
    public let positionUpdatedAt: Date?
    public let artworkPath: String?
    public let volume: Double?
    public let isMuted: Bool?
    public let features: RemoteMediaFeatures

    public var isActive: Bool { state == "playing" || state == "paused" }
    public var id: String { selection.id }
    public var trackId: String {
        // Metadata is needed when an integration reuses its stream URL across tracks.
        [contentId, title, artist, album].map { value in
            let value = value ?? ""
            return "\(value.utf8.count):\(value)"
        }.joined()
    }
}
