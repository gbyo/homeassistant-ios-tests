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
    /// Set once the host app has prepared the image; `nil` until then, so a session publishes its
    /// metadata immediately rather than waiting on a download.
    public let artwork: RemoteMediaArtworkDescriptor?
    public let volume: Double?
    public let isMuted: Bool?
    public let features: RemoteMediaFeatures

    public init(
        selection: RemoteMediaSelection,
        deviceName: String,
        deviceClass: String?,
        state: String,
        title: String?,
        artist: String?,
        album: String?,
        contentId: String?,
        duration: TimeInterval?,
        position: TimeInterval?,
        positionUpdatedAt: Date?,
        artwork: RemoteMediaArtworkDescriptor?,
        volume: Double?,
        isMuted: Bool?,
        features: RemoteMediaFeatures
    ) {
        self.selection = selection
        self.deviceName = deviceName
        self.deviceClass = deviceClass
        self.state = state
        self.title = title
        self.artist = artist
        self.album = album
        self.contentId = contentId
        self.duration = duration
        self.position = position
        self.positionUpdatedAt = positionUpdatedAt
        self.artwork = artwork
        self.volume = volume
        self.isMuted = isMuted
        self.features = features
    }

    /// What the player is doing, with the integrations' spelling variations collapsed.
    public var playback: RemoteMediaPlaybackState { .init(homeAssistantState: state) }

    /// Whether this report describes an actual piece of media.
    ///
    /// The session's lifetime hangs on this rather than on the playback state: a player that is
    /// paused, or briefly `idle` between tracks, still has something to show.
    public var hasMeaningfulMedia: Bool {
        contentId != nil || title != nil || artist != nil || album != nil || duration != nil
    }

    public var id: String { selection.id }
    public var trackId: String {
        // Metadata is needed when an integration reuses its stream URL across tracks.
        [contentId, title, artist, album].map { value in
            let value = value ?? ""
            return "\(value.utf8.count):\(value)"
        }.joined()
    }

    public func withState(_ state: String) -> Self {
        copy(state: state)
    }

    public func withPosition(_ position: TimeInterval?, updatedAt: Date?) -> Self {
        copy(position: position, positionUpdatedAt: updatedAt)
    }

    public func withArtwork(_ artwork: RemoteMediaArtworkDescriptor?) -> Self {
        copy(artwork: .some(artwork))
    }

    /// `artwork` is doubly optional so passing `nil` means "unchanged" while `.some(nil)` clears it.
    private func copy(
        state: String? = nil,
        position: TimeInterval?? = nil,
        positionUpdatedAt: Date?? = nil,
        artwork: RemoteMediaArtworkDescriptor?? = nil
    ) -> Self {
        .init(
            selection: selection,
            deviceName: deviceName,
            deviceClass: deviceClass,
            state: state ?? self.state,
            title: title,
            artist: artist,
            album: album,
            contentId: contentId,
            duration: duration,
            position: position ?? self.position,
            positionUpdatedAt: positionUpdatedAt ?? self.positionUpdatedAt,
            artwork: artwork ?? self.artwork,
            volume: volume,
            isMuted: isMuted,
            features: features
        )
    }
}
