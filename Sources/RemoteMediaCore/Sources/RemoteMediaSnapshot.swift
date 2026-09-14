import Foundation

/// Playback data for one followed `media_player`, free of credentials and of any dependency on the
/// frameworks that display it.
///
/// This is a **wire contract**, not just an app model: it is encoded as JSON and a Home Assistant
/// server has to be able to produce exactly this shape. Two rules follow, and both are deliberate:
///
/// - Every value is a primitive with an unambiguous JSON form. In particular `positionUpdatedAtUnix`
///   is **seconds since 1970-01-01 UTC**, not a `Date`: `JSONEncoder` writes a `Date` in Swift's
///   2001 reference epoch, and asking a Python server to reproduce that would be a permanent trap.
/// - Nothing secret may appear here. No token, no credential, no authenticated URL: this JSON
///   leaves the app's control, and anything in it leaves with it.
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
    /// When `position` was measured, in seconds since 1970-01-01 UTC.
    public let positionUpdatedAtUnix: TimeInterval?
    /// The prepared image, once there is one. It stays `nil` while artwork is still being
    /// prepared, so metadata can be published without waiting on a download.
    public let artwork: RemoteMediaArtworkDescriptor?
    /// What the absence of `artwork` means: still coming, or genuinely none. See
    /// `RemoteMediaArtworkDisposition`.
    public let artworkDisposition: RemoteMediaArtworkDisposition
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
        positionUpdatedAtUnix: TimeInterval?,
        artwork: RemoteMediaArtworkDescriptor?,
        artworkDisposition: RemoteMediaArtworkDisposition? = nil,
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
        self.positionUpdatedAtUnix = positionUpdatedAtUnix
        self.artwork = artwork
        self.artworkDisposition = artworkDisposition ?? (artwork == nil ? .deferred : .available)
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

    public func withPosition(_ position: TimeInterval?, updatedAtUnix: TimeInterval?) -> Self {
        copy(position: position, positionUpdatedAtUnix: updatedAtUnix)
    }

    public func withVolume(_ volume: Double?) -> Self {
        copy(volume: .some(volume))
    }

    /// The part of a command's outcome that is deterministic before the server reports back.
    /// Track-changing commands deliberately return `nil`: inventing their metadata would be worse
    /// than briefly showing the previous track.
    public func optimisticallyApplying(
        _ command: RemoteMediaCommand,
        value: Double? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Self? {
        switch command {
        case .play:
            withState("playing")
        case .pause:
            withState("paused")
        case .togglePlayPause:
            withState(playback.isPlaying ? "paused" : "playing")
        case .stop:
            withState("idle")
        case .seek:
            value.map { withPosition(command.clamped($0), updatedAtUnix: now) }
        case .volume:
            value.map { withVolume(command.clamped($0)) }
        case .previous, .next:
            nil
        }
    }

    public func withArtwork(_ artwork: RemoteMediaArtworkDescriptor?) -> Self {
        copy(
            artwork: .some(artwork),
            artworkDisposition: artwork == nil ? .absent : .available
        )
    }

    public func withDeferredArtwork() -> Self {
        copy(artwork: .some(nil), artworkDisposition: .deferred)
    }

    /// `artwork` is doubly optional so passing `nil` means "unchanged" while `.some(nil)` clears it.
    private func copy(
        state: String? = nil,
        position: TimeInterval?? = nil,
        positionUpdatedAtUnix: TimeInterval?? = nil,
        artwork: RemoteMediaArtworkDescriptor?? = nil,
        artworkDisposition: RemoteMediaArtworkDisposition? = nil,
        volume: Double?? = nil
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
            positionUpdatedAtUnix: positionUpdatedAtUnix ?? self.positionUpdatedAtUnix,
            artwork: artwork ?? self.artwork,
            artworkDisposition: artworkDisposition ?? self.artworkDisposition,
            volume: volume ?? self.volume,
            isMuted: isMuted,
            features: features
        )
    }
}
