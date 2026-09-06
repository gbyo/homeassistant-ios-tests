import Foundation
import NowPlaying
import Observation
import Shared

@MainActor
@Observable
final class HomeAssistantRemoteMediaSession: RemoteMediaSessionRepresentable {
    let id: String
    private var attributes: Shared.RemoteMediaSessionAttributes
    private let artworkLoader = RemoteMediaArtworkLoader()

    init(attributes: Shared.RemoteMediaSessionAttributes) {
        self.id = attributes.id
        self.attributes = attributes
    }

    func update(_ attributes: Shared.RemoteMediaSessionAttributes) {
        guard attributes.id == id else { return }
        self.attributes = attributes
        Current.Log.verbose("Remote media extension received state: \(attributes.snapshot.state)")
    }

    var playbackSnapshot: MediaPlaybackSnapshot? {
        let snapshot = attributes.snapshot
        guard snapshot.isActive else { return nil }
        return .init(
            state: snapshot.state == "playing" ? .playing() : .paused,
            elapsedTime: snapshot.position,
            timestamp: snapshot.positionUpdatedAt
        )
    }

    var content: (any MediaContentRepresentable)? {
        let snapshot = attributes.snapshot
        guard snapshot.isActive else { return nil }
        let artwork: Artwork? = snapshot.artworkPath.flatMap { path in
            guard !path.isEmpty else { return nil }
            let loader = artworkLoader
            return Artwork(id: snapshot.id + snapshot.trackId + path) { _ in
                try await ArtworkRepresentation(data: loader.data(for: snapshot))
            }
        }
        return MusicContent(
            id: snapshot.trackId,
            songTitle: snapshot.title ?? snapshot.deviceName,
            artistName: snapshot.artist ?? "",
            albumName: snapshot.album ?? "",
            type: snapshot.deviceClass == "tv" ? .video : .audio,
            duration: snapshot.duration.map { .finite($0) },
            artwork: artwork
        )
    }

    var commands: [MediaCommand] {
        let snapshot = attributes.snapshot
        guard snapshot.isActive else { return [] }
        let selection = snapshot.selection
        return RemoteMediaCommand.allCases.filter { snapshot.features.commands.contains($0) }.compactMap { command in
            switch command {
            case .play: return .play { try await RemoteMediaCommandExecutor().execute(.play, selection: selection) }
            case .pause: return .pause { try await RemoteMediaCommandExecutor().execute(.pause, selection: selection) }
            case .togglePlayPause:
                return .togglePlayPause { try await RemoteMediaCommandExecutor().execute(
                    .togglePlayPause,
                    selection: selection
                ) }
            case .stop: return .stop { try await RemoteMediaCommandExecutor().execute(.stop, selection: selection) }
            case .previous:
                return .previous { try await RemoteMediaCommandExecutor().execute(.previous, selection: selection) }
            case .next: return .next { try await RemoteMediaCommandExecutor().execute(.next, selection: selection) }
            case .seek:
                return .seekToPosition { try await RemoteMediaCommandExecutor().execute(
                    .seek,
                    selection: selection,
                    value: $0
                ) }
            case .volume: return nil // Volume is a device capability, not a MediaCommand.
            }
        }
    }

    var devices: [MediaDevice] {
        let snapshot = attributes.snapshot
        var capabilities: [MediaDevice.Capability] = []
        if snapshot.features.contains(.volumeSet), let volume = snapshot.volume {
            let selection = snapshot.selection
            capabilities.append(.absoluteVolume(Float(volume)) { value in
                try await RemoteMediaCommandExecutor().execute(.volume, selection: selection, value: Double(value))
            })
        }
        return [.init(
            id: id,
            name: snapshot.deviceName,
            type: snapshot.deviceClass == "tv" ? .tv : .speaker,
            capabilities: capabilities
        )]
    }
}
