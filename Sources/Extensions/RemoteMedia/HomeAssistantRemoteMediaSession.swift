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
    private let gate = RemoteMediaReconciliationGate()

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
        // A framework push is authoritative over any command readback already in flight.
        gate.invalidate()
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

    var commands: [MediaCommand] {
        let snapshot = snapshot
        guard snapshot.hasMeaningfulMedia else { return [] }
        return RemoteMediaCommand.allCases
            .filter { snapshot.features.commands.contains($0) }
            .compactMap { command in
                switch command {
                case .play: return .play { try await self.send(.play) }
                case .pause: return .pause { try await self.send(.pause) }
                case .togglePlayPause: return .togglePlayPause { try await self.send(.togglePlayPause) }
                case .stop: return .stop { try await self.send(.stop) }
                case .previous: return .previous { try await self.send(.previous) }
                case .next: return .next { try await self.send(.next) }
                case .seek: return .seekToPosition { try await self.send(.seek, value: $0) }
                case .volume: return nil
                }
            }
    }

    var devices: [MediaDevice] {
        var capabilities: [MediaDevice.Capability] = []
        if snapshot.features.contains(.volumeSet), let volume = snapshot.volume {
            capabilities.append(.absoluteVolume(Float(volume)) { value in
                try await self.send(.volume, value: Double(value))
            })
        }
        return [.init(
            id: id,
            name: snapshot.deviceName,
            type: snapshot.deviceClass == "tv" ? .tv : .speaker,
            capabilities: capabilities
        )]
    }

    private func send(_ command: RemoteMediaCommand, value: Double? = nil) async throws {
        guard let lifetime,
              let context = RemoteMediaTransportStore.load(
                  matching: snapshot.selection,
                  lifetime: lifetime
              ) else {
            throw RemoteMediaWebhookClient.ClientError.noTransportContext
        }
        let selection = snapshot.selection
        guard context.selection == selection, context.lifetime == lifetime else {
            throw RemoteMediaError.noLongerFollowing
        }
        let client = RemoteMediaWebhookClient()
        let generation = gate.begin()
        let condition = RemoteMediaSettleCondition.forCommand(command, value: value, previous: snapshot)
        do {
            try await client.send(
                command,
                value: value,
                selection: selection,
                lifetime: lifetime,
                context: context
            )
        } catch {
            client.endBurst()
            throw error
        }
        if let optimistic = snapshot.optimisticallyApplying(command, value: value) {
            apply(optimistic)
        }
        startReconciling(
            until: condition,
            generation: generation,
            selection: selection,
            lifetime: lifetime,
            client: client
        )
    }

    private func startReconciling(
        until condition: RemoteMediaSettleCondition,
        generation: Int,
        selection: RemoteMediaSelection,
        lifetime: RemoteMediaFollowLifetime,
        client: RemoteMediaWebhookClient
    ) {
        let reconciler = RemoteMediaReconciler {
            guard let context = RemoteMediaTransportStore.load(
                matching: selection,
                lifetime: lifetime
            ) else {
                throw RemoteMediaWebhookClient.ClientError.noTransportContext
            }
            return try await client.readState(selection: selection, lifetime: lifetime, context: context)
        }
        let task = Task { [weak self] in
            await reconciler.reconcile(until: condition) { readback in
                await MainActor.run {
                    guard let self, self.gate.isCurrent(generation) else { return }
                    self.applyReadback(readback)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                gate.finish(generation)
                client.endBurst()
                #if DEBUG
                RemoteMediaFootprint.log("settled")
                #endif
            }
        }
        gate.track(task, for: generation)
    }

    private func applyReadback(_ readback: RemoteMediaStateReadback) {
        switch readback {
        case let .entity(state):
            apply(state.snapshot)
        case .missing, .unreadable:
            RemoteMediaLog.logger.debug("reconcile produced no usable state")
        }
    }

    private func apply(_ incoming: RemoteMediaSnapshot) {
        guard let reduced = RemoteMediaSnapshotReducer.reduce(previous: snapshot, incoming: incoming),
              reduced != snapshot else { return }
        snapshot = reduced
    }
}
