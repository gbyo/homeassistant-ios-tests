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
        RemoteMediaLog.logger.debug("Received state: \(attributes.snapshot.state, privacy: .public)")
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
        let artworkPathKind = snapshot.artworkPath.flatMap { URL(string: $0)?.scheme == nil ? "relative" : "absolute" }
            ?? "none"
        let contentDiagnostic = "content track=\(snapshot.trackId) " +
            "artwork present=\(snapshot.artworkPath?.isEmpty == false ? "yes" : "no") " +
            "artwork path kind=\(artworkPathKind)"
        RemoteMediaLog.logger.debug("\(contentDiagnostic, privacy: .public)")
        let artwork: Artwork? = snapshot.artworkPath.flatMap { path in
            guard !path.isEmpty else { return nil }
            let loader = artworkLoader
            RemoteMediaLog.logger.debug("artwork constructed")
            return Artwork(id: snapshot.id + snapshot.trackId + path) { size in
                RemoteMediaLog.logger.debug(
                    "artwork requested width=\(size.width, privacy: .public) height=\(size.height, privacy: .public)"
                )
                do {
                    let data = try await loader.data(for: snapshot)
                    RemoteMediaLog.logger.debug("artwork decode handoff")
                    let representation = try ArtworkRepresentation(data: data)
                    RemoteMediaLog.logger.debug("artwork representation decoded")
                    return representation
                } catch {
                    let diagnostic = "artwork callback failed type=\(String(reflecting: type(of: error))) " +
                        "description=\(error.localizedDescription)"
                    RemoteMediaLog.logger.error("\(diagnostic, privacy: .public)")
                    throw error
                }
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
        let mappedCommands = snapshot.features.commands.map(\.rawValue).sorted().joined(separator: ",")
        let commandDiagnostic = "supported_features=\(snapshot.features.rawValue) mapped commands=[\(mappedCommands)]"
        RemoteMediaLog.logger.debug("\(commandDiagnostic, privacy: .public)")
        return RemoteMediaCommand.allCases.filter { snapshot.features.commands.contains($0) }.compactMap { command in
            switch command {
            case .play:
                return .play {
                    RemoteMediaLog.logger.info("command callback invoked: play")
                    try await RemoteMediaCommandExecutor().execute(.play, selection: selection)
                }
            case .pause:
                return .pause {
                    RemoteMediaLog.logger.info("command callback invoked: pause")
                    try await RemoteMediaCommandExecutor().execute(.pause, selection: selection)
                }
            case .togglePlayPause:
                return .togglePlayPause {
                    RemoteMediaLog.logger.info("command callback invoked: togglePlayPause")
                    try await RemoteMediaCommandExecutor().execute(.togglePlayPause, selection: selection)
                }
            case .stop:
                return .stop {
                    RemoteMediaLog.logger.info("command callback invoked: stop")
                    try await RemoteMediaCommandExecutor().execute(.stop, selection: selection)
                }
            case .previous:
                return .previous {
                    RemoteMediaLog.logger.info("command callback invoked: previous")
                    try await RemoteMediaCommandExecutor().execute(.previous, selection: selection)
                }
            case .next:
                return .next {
                    RemoteMediaLog.logger.info("command callback invoked: next")
                    try await RemoteMediaCommandExecutor().execute(.next, selection: selection)
                }
            case .seek:
                return .seekToPosition { position in
                    RemoteMediaLog.logger.info(
                        "command callback invoked: seek position=\(position, privacy: .public)"
                    )
                    try await RemoteMediaCommandExecutor().execute(.seek, selection: selection, value: position)
                }
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
                RemoteMediaLog.logger.info("volume callback invoked value=\(value, privacy: .public)")
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
