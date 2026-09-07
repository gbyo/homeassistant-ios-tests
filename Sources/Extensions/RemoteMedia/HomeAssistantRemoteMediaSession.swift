import CryptoKit
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

    /// Registers this session's push token with Home Assistant, and re-offers it whenever the
    /// Follow lifetime changes under it.
    @ObservationIgnored private let registrar = RemoteMediaSessionRegistrar()
    @ObservationIgnored private var pushTokens: RemoteMediaPushTokenObserver?

    init(attributes: RemoteMediaSessionAttributes) {
        self.id = attributes.id
        self.snapshot = attributes.snapshot
        self.selection = attributes.snapshot.selection
        self.context = RemoteMediaTransportStore.load()
        registrar.adopt(lifetime: attributes.lifetime)
        RemoteMediaLog.logger
            .info("session created following \(attributes.snapshot.selection.entityId, privacy: .public)")
    }

    /// Starts watching for this session's own APNs update token, which is what lets Home Assistant
    /// refresh the card while nothing of ours is running.
    ///
    /// Called after `session(_:)` returns rather than from `init`: the framework associates this
    /// object with a system session only once it has been handed back, and there is no token to
    /// read until it has.
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
        RemoteMediaLog.logger.info(
            "update pid=\(getpid(), privacy: .public) session=\(attributes.id, privacy: .public) state=\(attributes.snapshot.state, privacy: .public) title=\(attributes.snapshot.title ?? "-", privacy: .public)"
        )
        // Whether the cover for the incoming track is already on disk, logged here because it
        // decides whether the system's first artwork request can possibly be answered — and so
        // whether anything depends on the session being republished afterwards at all.
        if let descriptor = attributes.snapshot.artwork {
            let key = descriptor.resolvedKey(sessionId: id, trackId: attributes.snapshot.trackId)
            let onDisk = key.map { RemoteMediaArtworkCache.contains(.init(cacheKey: $0)) } ?? false
            RemoteMediaLog.logger.info(
                """
                artwork update artworkId=\(Self.shortId(descriptor.identity), privacy: .public) \
                cached=\(onDisk, privacy: .public)
                """
            )
        }
        // The host app is authoritative when it is running, but a reconciliation already in flight
        // is answering a command the user just pressed, so it is not thrown away here.
        apply(attributes.snapshot)
        if context == nil { context = RemoteMediaTransportStore.load() }
        // Following the same player again is a new relationship, so the token has to be
        // registered against it even when the token itself has not changed.
        registrar.adopt(lifetime: attributes.lifetime)
        if let token = pushToken { register(RemoteMediaPushToken(token)) }
    }

    /// Offers the session's update token to Home Assistant, which is what lets the server push this
    /// card's state while nothing of ours is running.
    private func register(_ token: RemoteMediaPushToken) {
        let context = context ?? RemoteMediaTransportStore.load()
        self.context = context
        registrar.offer(
            token: token,
            sessionId: id,
            serverId: selection.serverId,
            entityId: selection.entityId,
            context: context
        )
    }

    // MARK: - Artwork

    /// The cover the system has already been given bytes for, if it had to be fetched first.
    ///
    /// Observed, and the whole mechanism behind a cold cover appearing. See `content`.
    private var readyArtworkIdentity: String?
    /// The cover being fetched, so a burst of requests for the same one is a single download.
    @ObservationIgnored private var fetchingArtworkIdentity: String?

    /// A short, stable label for an artwork identity.
    ///
    /// The identity is the source URL on a push from Home Assistant, so it is never logged whole —
    /// a capture needs to tell two identities apart, not to reproduce either.
    nonisolated private static func shortId(_ identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    /// The cached bytes for this track's cover, without ever going to the network.
    ///
    /// Synchronous on purpose. This is called from inside a RemoteMedia callback, and
    /// `mediaremoted` watchdogs a session that holds one open — so nothing here may wait for
    /// anything, including a fetch that would otherwise be about to succeed.
    nonisolated private static func cachedArtwork(
        for descriptor: RemoteMediaArtworkDescriptor,
        sessionId: String,
        trackId: String
    ) -> Data? {
        guard let key = descriptor.resolvedKey(sessionId: sessionId, trackId: trackId) else {
            RemoteMediaLog.logger.info("artwork cache result=no key")
            return nil
        }
        let file = RemoteMediaArtworkDescriptor(cacheKey: key)
        let data = RemoteMediaArtworkCache.data(for: file)
        RemoteMediaLog.logger.info(
            """
            artwork cache result=\(data == nil ? "miss" : "hit", privacy: .public) \
            key=\(key.prefix(8), privacy: .public) \
            bytes=\(data?.count ?? 0, privacy: .public)
            """
        )
        return data
    }

    /// Fetches a cover that is not cached yet, then asks the system to come back for it.
    ///
    /// The system abandons an artwork request that does not answer promptly, so awaiting a
    /// download inside the provider does not produce a picture — it produces a fetch whose result
    /// arrives after the only request that wanted it has gone. That is why a cold cover used to
    /// appear one track late: the bytes were right, the request they belonged to was over.
    ///
    /// So the download happens out here instead, and when it lands the artwork's identity changes
    /// once. A different identity is a different cover as far as the system is concerned, which is
    /// what makes it ask again for something it has already been told is unavailable. Nothing
    /// about the track changes, and it happens at most once per cover: the guards below are what
    /// stop it becoming a loop.
    private func beginArtworkFetch(
        _ descriptor: RemoteMediaArtworkDescriptor,
        sessionId: String,
        trackId: String
    ) {
        let identity = descriptor.identity
        guard let url = descriptor.url else {
            RemoteMediaLog.logger.info("artwork fetch result=no fetchable source")
            return
        }
        guard fetchingArtworkIdentity != identity, readyArtworkIdentity != identity else { return }
        fetchingArtworkIdentity = identity
        RemoteMediaLog.logger.info(
            "artwork fetch start host=\(RemoteMediaArtworkFetcher.Outcome.host(of: url), privacy: .public)"
        )

        Task { [weak self] in
            let outcome = await RemoteMediaArtworkFetcher.fetch(from: url)
            await MainActor.run {
                guard let self else { return }
                if fetchingArtworkIdentity == identity { fetchingArtworkIdentity = nil }
                RemoteMediaLog.logger.info(
                    """
                    artwork fetch status=\(outcome.status ?? 0, privacy: .public) \
                    mime=\(outcome.mimeType ?? "-", privacy: .public) \
                    bytes=\(outcome.byteCount, privacy: .public) \
                    result=\(outcome.reason, privacy: .public)
                    """
                )
                guard let data = outcome.data else { return }
                guard let key = descriptor.resolvedKey(sessionId: sessionId, trackId: trackId) else {
                    RemoteMediaLog.logger.error("artwork store result=no key")
                    return
                }
                let file = RemoteMediaArtworkDescriptor(cacheKey: key)
                do {
                    try RemoteMediaArtworkCache.store(data, for: file)
                } catch {
                    RemoteMediaLog.logger.error("artwork store result=failed")
                    return
                }
                // Read back rather than assumed: republishing for bytes that are not actually
                // readable would spend the one refresh this cover gets on another empty answer.
                guard RemoteMediaArtworkCache.contains(file) else {
                    RemoteMediaLog.logger.error(
                        "artwork store result=not readable key=\(key.prefix(8), privacy: .public)"
                    )
                    return
                }
                RemoteMediaLog.logger.info(
                    "artwork store result=ok key=\(key.prefix(8), privacy: .public)"
                )
                // The one republication. `readyArtworkIdentity` is observed, so this is what makes
                // the system ask again — and having been set, the guard above means it cannot ask
                // for a fetch a second time.
                readyArtworkIdentity = identity
                RemoteMediaLog.logger.info(
                    """
                    artwork refresh requested \
                    oldId=\(Self.shortId(identity), privacy: .public) \
                    newId=\(Self.shortId(identity), privacy: .public)#ready
                    """
                )
            }
        }
    }

    // MARK: - What the system renders

    var playbackSnapshot: MediaPlaybackSnapshot? {
        guard snapshot.hasMeaningfulMedia else { return nil }
        return .init(
            state: snapshot.playback.isPlaying ? .playing() : .paused,
            elapsedTime: snapshot.position,
            // The only place the wire's Unix seconds become a `Date`.
            timestamp: snapshot.positionUpdatedAtUnix.map(Date.init(timeIntervalSince1970:))
        )
    }

    var content: (any MediaContentRepresentable)? {
        let snapshot = snapshot
        guard snapshot.hasMeaningfulMedia else { return nil }
        // Read here rather than inside the closure: this is the observed property whose change is
        // what asks the system to come back for a cover that has since arrived.
        let ready = readyArtworkIdentity
        let artwork = snapshot.artwork.map { descriptor in
            let identity = descriptor.identity
            // A cover that has arrived since the system last asked is deliberately a *different*
            // artwork, because that is what makes it ask again. See `beginArtworkFetch`.
            let requested = ready == identity ? "\(identity)#ready" : identity
            // Emitted on every read of `content`. If a `refresh requested` is not followed by one
            // of these carrying the `#ready` identity, the system did not come back — which means
            // Observation is not what republishes this session, and the mechanism is wrong rather
            // than the bytes.
            RemoteMediaLog.logger.info(
                """
                artwork content recomputed \
                artworkId=\(Self.shortId(identity), privacy: .public)\
                \(ready == identity ? "#ready" : "", privacy: .public) \
                source=\(descriptor.url == nil ? "none" : "remote", privacy: .public) \
                prepared=\(descriptor.cacheKey == nil ? "no" : "yes", privacy: .public)
                """
            )
            return Artwork(id: requested) { [weak self, id, trackId = snapshot.trackId] size in
                RemoteMediaLog.logger.info(
                    """
                    artwork provider entered \
                    requested=\(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public)
                    """
                )
                guard let data = Self.cachedArtwork(for: descriptor, sessionId: id, trackId: trackId) else {
                    // Answer now and fetch behind it. Awaiting the download here is what produced
                    // a cover that only appeared on the following track.
                    await self?.beginArtworkFetch(descriptor, sessionId: id, trackId: trackId)
                    RemoteMediaLog.logger.info("artwork provider returned=nil reason=not cached yet")
                    throw RemoteMediaError.invalidArtwork
                }
                // Decoded at the requested size, not the stored size: a full-size decode cost
                // around a megabyte of a 6144 KB ledger for an image rendered far smaller.
                // Encoded bytes, never a `CGImage`. The reply to this callback is serialized over
                // NSXPC, and an image object in the returned graph makes `NSXPCEncoder` throw —
                // which is what crashed the extension the moment this path first started
                // returning pixels rather than being abandoned.
                guard let encoded = RemoteMediaArtworkCache.thumbnailData(from: data, requestedSize: size) else {
                    RemoteMediaLog.logger.error("artwork provider returned=nil reason=decode failed")
                    throw RemoteMediaError.invalidArtwork
                }
                #if DEBUG
                RemoteMediaFootprint.log("artwork \(encoded.count) bytes")
                #endif
                RemoteMediaLog.logger.info(
                    "artwork provider representation=data bytes=\(encoded.count, privacy: .public)"
                )
                return try ArtworkRepresentation(data: encoded)
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
            RemoteMediaLog.logger.error("command \(command.rawValue, privacy: .public): no transport context")
            throw RemoteMediaWebhookClient.ClientError.noTransportContext
        }

        // Claim a generation before the command goes out, so a reply to an older one cannot land
        // on top of this. Claiming also cancels the reconciliation still running for the last.
        let generation = gate.begin()

        let condition = RemoteMediaSettleCondition.forCommand(command, value: value, previous: snapshot)
        do {
            try await client.send(command, value: value, selection: selection, context: context)
        } catch {
            RemoteMediaLog.logger.error(
                "command \(command.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
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
                    // A slow reply to an older command must not land on the track a newer one
                    // has since reached.
                    guard let self, self.gate.isCurrent(generation) else { return }
                    self.applyReadback(readback)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                gate.finish(generation)
                // The command and its read-backs are done, so let go of the connection they shared.
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
            // Neither is a reason to change what is on screen. A missing entity ends the session
            // through the host app, which owns the followed selection.
            RemoteMediaLog.logger.debug("reconcile produced no usable state")
        }
    }

    /// Runs every incoming snapshot through the reducer, so a transient `idle` or a momentarily
    /// blank set of attributes never empties the card.
    private func apply(_ incoming: RemoteMediaSnapshot) {
        guard let reduced = RemoteMediaSnapshotReducer.reduce(previous: snapshot, incoming: incoming),
              reduced != snapshot else { return }
        snapshot = reduced
    }
}
