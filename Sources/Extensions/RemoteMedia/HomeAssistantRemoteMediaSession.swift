import Foundation
import NowPlaying
import Observation

/// Minimal system session representation. Controls and artwork are layered on separately.
@MainActor
@Observable
final class HomeAssistantRemoteMediaSession: RemoteMediaSessionRepresentable {
    let id: String
    private var snapshot: RemoteMediaSnapshot
    private var lifetime: RemoteMediaFollowLifetime?

    @ObservationIgnored private let registrar = RemoteMediaSessionRegistrar()
    @ObservationIgnored private var pushTokens: RemoteMediaPushTokenObserver?

    init(attributes: RemoteMediaSessionAttributes) {
        self.id = attributes.id
        self.snapshot = attributes.snapshot
        self.lifetime = attributes.lifetime
        registrar.adopt(lifetime: attributes.lifetime)
        RemoteMediaLog.logger
            .info("session created following \(attributes.snapshot.selection.entityId, privacy: .public)")
    }

    func startObservingPushToken() {
        guard pushTokens == nil else { return }
        let observer = RemoteMediaPushTokenObserver(
            currentToken: { [weak self] in self?.pushToken },
            tokenUpdates: { [weak self] in self?.pushTokenUpdates ?? AsyncStream { $0.finish() } },
            onToken: { [weak self] token in self?.register(token) }
        )
        pushTokens = observer
        observer.start()
    }

    func update(_ attributes: RemoteMediaSessionAttributes) {
        guard attributes.id == id else { return }
        let previousSelection = snapshot.selection
        snapshot = attributes.snapshot
        lifetime = attributes.lifetime
        if previousSelection != attributes.snapshot.selection, let lifetime = attributes.lifetime {
            RemoteMediaAuthoritativeSelectionStore.save(
                .init(sessionId: id, lifetime: lifetime, selection: attributes.snapshot.selection)
            )
        }
        registrar.adopt(lifetime: attributes.lifetime)
        if let token = pushToken { register(RemoteMediaPushToken(token)) }
    }

    private func register(_ token: RemoteMediaPushToken) {
        let context = lifetime.flatMap {
            RemoteMediaTransportStore.load(matching: snapshot.selection, lifetime: $0)
        }
        registrar.offer(
            token: token,
            sessionId: id,
            serverId: snapshot.selection.serverId,
            entityId: snapshot.selection.entityId,
            context: context
        )
    }

    var playbackSnapshot: MediaPlaybackSnapshot? {
        guard snapshot.hasMeaningfulMedia else { return nil }
        return .init(
            state: snapshot.playback.isPlaying ? .playing() : .paused,
            elapsedTime: snapshot.position,
            timestamp: snapshot.positionUpdatedAtUnix.map(Date.init(timeIntervalSince1970:))
        )
    }

    var content: (any MediaContentRepresentable)? {
        guard snapshot.hasMeaningfulMedia else { return nil }
        return MusicContent(
            id: snapshot.trackId,
            songTitle: snapshot.title ?? snapshot.deviceName,
            artistName: snapshot.artist ?? "",
            albumName: snapshot.album ?? "",
            type: snapshot.deviceClass == "tv" ? .video : .audio,
            duration: snapshot.duration.map { .finite($0) },
            artwork: nil
        )
    }

    var commands: [MediaCommand] { [] }

    var devices: [MediaDevice] {
        [.init(
            id: id,
            name: snapshot.deviceName,
            type: snapshot.deviceClass == "tv" ? .tv : .speaker,
            capabilities: []
        )]
    }
}
