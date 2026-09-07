import Foundation
import NowPlaying
import Observation

/// The Now Playing session the system drives, kept deliberately small.
///
/// This process has a hard 6144 KB jetsam ledger, so it links no Companion framework and does no
/// work the host app can do instead: artwork arrives pre-fetched and pre-sized in the App Group,
/// and a command is one webhook POST with no entity-state round trip beforehand.
///
/// The snapshot here is mutable rather than a frozen copy of whatever the host app last published.
/// The system keeps this object alive between commands, so a command issued from Control Center is
/// reconciled against Home Assistant here — otherwise pressing Next changes the speaker while the
/// card keeps showing the old song until the containing app is next opened.
@MainActor
@Observable
final class HomeAssistantRemoteMediaSession: RemoteMediaSessionRepresentable {
    let id: String
    /// What the card currently shows. Updated by the host app through `update`, and by this
    /// process's own reconciliation after a command.
    private var snapshot: RemoteMediaSnapshot
    private let selection: RemoteMediaSelection
    /// One client and one context read, refreshed only when the session's identity changes.
    private let client = RemoteMediaWebhookClient()
    private var context: RemoteMediaTransportContext?

    /// Rapid Control Center use overlaps commands, and a slow reply to Next #1 must never overwrite
    /// the track Next #3 landed on.
    private let gate = RemoteMediaReconciliationGate()

    init(attributes: RemoteMediaSessionAttributes) {
        self.id = attributes.id
        self.snapshot = attributes.snapshot
        self.selection = attributes.snapshot.selection
        self.context = RemoteMediaTransportStore.load()
        RemoteMediaFootprint.log("session init")
        RemoteMediaProbeLog.record("ext", "session init artwork=\(attributes.snapshot.artwork?.cacheKey ?? "NONE") " +
            "context=\(context != nil) urls=\(context?.webhookURLs.count ?? 0)")
    }

    func update(_ attributes: RemoteMediaSessionAttributes) {
        guard attributes.id == id else { return }
        // The host app is authoritative when it is running, but a reconciliation already in flight
        // is answering a command the user just pressed, so it is not thrown away here.
        apply(attributes.snapshot, from: "host")
        if context == nil { context = RemoteMediaTransportStore.load() }
    }

    // MARK: - What the system renders

    var playbackSnapshot: MediaPlaybackSnapshot? {
        guard snapshot.hasMeaningfulMedia else { return nil }
        return .init(
            state: snapshot.playback.isPlaying ? .playing() : .paused,
            elapsedTime: snapshot.position,
            timestamp: snapshot.positionUpdatedAt
        )
    }

    var content: (any MediaContentRepresentable)? {
        let snapshot = snapshot
        guard snapshot.hasMeaningfulMedia else { return nil }
        RemoteMediaProbeLog.record("ext", "content built artwork key=\(snapshot.artwork?.cacheKey ?? "NONE")")
        let artwork = snapshot.artwork.map { descriptor in
            // Keyed on the descriptor so a new track's image replaces the previous one.
            Artwork(id: descriptor.cacheKey) { _ in
                RemoteMediaFootprint.log("artwork callback")
                // The key is published before the file exists, so wait for the host app to finish
                // writing it rather than reporting no artwork and never being asked again.
                guard let data = await RemoteMediaArtworkCache.data(
                    for: descriptor,
                    waitingForPreparation: true
                ) else {
                    RemoteMediaProbeLog.record("ext", "artwork MISSING from cache after waiting")
                    throw RemoteMediaError.invalidArtwork
                }
                RemoteMediaProbeLog.record("ext", "artwork representation bytes=\(data.count)")
                return try ArtworkRepresentation(data: data)
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
                case .volume: return nil // Volume is a device capability, not a MediaCommand.
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

    // MARK: - Commands

    /// One webhook POST per user action, then a bounded read-back so the card reflects what the
    /// speaker actually did. A failure is reported to the system and logged; it never tears the
    /// session down, because the user is still following this player.
    private func send(_ command: RemoteMediaCommand, value: Double? = nil) async throws {
        let context = context ?? RemoteMediaTransportStore.load()
        self.context = context
        guard let context else {
            RemoteMediaProbeLog.record("ext", "command \(command.rawValue): NO TRANSPORT CONTEXT")
            throw RemoteMediaWebhookClient.ClientError.noTransportContext
        }

        // Claim a generation before the command goes out, so a reply to an older one cannot land
        // on top of this. Claiming also cancels the reconciliation still running for the last.
        let generation = gate.begin()

        let condition = RemoteMediaSettleCondition.forCommand(command, value: value, previous: snapshot)
        do {
            try await client.send(command, value: value, selection: selection, context: context)
            RemoteMediaFootprint.log("command \(command.rawValue)")
        } catch {
            RemoteMediaProbeLog.record("ext", "command \(command.rawValue) FAILED " +
                "type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
            throw error
        }
        startReconciling(until: condition, generation: generation, context: context)
    }

    private func startReconciling(
        until condition: RemoteMediaSettleCondition,
        generation: Int,
        context: RemoteMediaTransportContext
    ) {
        let reconciler = RemoteMediaReconciler { [client, selection] in
            try await client.readState(selection: selection, context: context)
        }
        let task = Task { [weak self] in
            await reconciler.reconcile(until: condition) { readback in
                await MainActor.run {
                    guard let self, self.gate.isCurrent(generation) else {
                        RemoteMediaProbeLog.record("ext", "stale reconciliation ignored gen=\(generation)")
                        return
                    }
                    self.applyReadback(readback)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.gate.finish(generation)
                RemoteMediaFootprint.log("reconcile done")
            }
        }
        gate.track(task, for: generation)
    }

    private func applyReadback(_ readback: RemoteMediaStateReadback) {
        switch readback {
        case let .entity(state):
            apply(state.snapshot, from: "reconcile")
        case .missing, .unreadable:
            // Neither is a reason to change what is on screen. A missing entity ends the session
            // through the host app, which owns the followed selection.
            RemoteMediaProbeLog.record("ext", "reconcile readback=\(readback)")
        }
    }

    /// Runs every incoming snapshot through the reducer, so a transient `idle` or a momentarily
    /// blank set of attributes never empties the card.
    private func apply(_ incoming: RemoteMediaSnapshot, from source: String) {
        guard let reduced = RemoteMediaSnapshotReducer.reduce(previous: snapshot, incoming: incoming) else {
            return
        }
        guard reduced != snapshot else { return }
        snapshot = reduced
        RemoteMediaProbeLog.record("ext", "\(source) applied playback=\(reduced.playback.rawValue) " +
            "artwork=\(reduced.artwork?.cacheKey.prefix(12) ?? "NONE") title=\(reduced.title ?? "-")")
    }
}
