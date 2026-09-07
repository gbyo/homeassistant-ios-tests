#if !targetEnvironment(macCatalyst)
import HAKit
import Shared
import UIKit

@available(iOS 27.0, *)
@MainActor
final class RemoteMediaCoordinator: ObservableObject, ServerObserver {
    static let shared = RemoteMediaCoordinator()

    @Published private(set) var selection: RemoteMediaSelection?
    @Published private(set) var snapshot: RemoteMediaSnapshot?
    @Published private(set) var error: String?
    private let publisher: RemoteMediaSessionPublisher
    private let artwork = RemoteMediaArtworkPreparer()
    private var subscription: HACancellable?
    private var foregroundObserver: NSObjectProtocol?
    private var generation = 0
    private var hasPublished = false
    private var artworkTask: Task<Void, Never>?
    /// The artwork identity currently attached or being prepared, so repeated state deliveries for
    /// the same track neither restart preparation nor drop the image that is already showing.
    private var artworkKey: String?

    convenience init() {
        self.init(publisher: .init(driver: AppleRemoteMediaSessionDriver()))
    }

    init(publisher: RemoteMediaSessionPublisher) {
        self.publisher = publisher
        self.selection = Current.settingsStore.remoteMediaSelection
        publisher.onError = { [weak self] error in
            self?.error = error == nil ? nil : L10n.RemoteMedia.sessionError
        }
    }

    func start() {
        guard foregroundObserver == nil else { return }
        Current.servers.add(observer: self)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func follow(_ selection: RemoteMediaSelection?) {
        guard selection == nil || selection?.entityId.hasPrefix("media_player.") == true else { return }
        Current.settingsStore.remoteMediaSelection = selection
        // Each Follow is its own lifetime. Re-following the same player reuses the session
        // identifier, so this is what lets the server retire the token the last one registered.
        Current.settingsStore.startRemoteMediaSessionGeneration(following: selection)
        self.selection = selection
        publisher.publish(nil)
        if selection == nil {
            // Nothing followed: the extension must not keep a usable webhook secret or stale art.
            RemoteMediaTransportStore.clear()
            RemoteMediaArtworkCache.removeAll()
        }
        refresh()
    }

    func refresh() {
        generation += 1
        let generation = generation
        subscription?.cancel()
        subscription = nil
        artworkTask?.cancel()
        artworkTask = nil
        artworkKey = nil
        snapshot = nil
        hasPublished = false
        error = nil
        // The extension evaluates no network state of its own, so the routes and the secret it uses
        // are refreshed here whenever the followed player or the server's connection changes.
        RemoteMediaTransportContextWriter.update(for: selection)
        guard let selection,
              let server = Current.servers.server(forServerIdentifier: selection.serverId),
              let api = Current.api(for: server) else {
            publisher.publish(nil)
            return
        }
        // Ask the server for this entity alone where it can filter, so following one player does not
        // stream every entity's state to the phone. Older servers send the unfiltered cache instead.
        var filter: [String: Any] = [:]
        if server.info.version > .canSubscribeEntitiesChangesWithFilter {
            filter = ["include": ["entities": [selection.entityId]]]
        }
        api.connectWebSocketIfNeeded()
        // HAKit's cache already handles reconnects and initial state delivery.
        subscription = api.connection.caches.states(filter).subscribe { [weak self] _, states in
            let state = states[selection.entityId]
                .flatMap { RemoteMediaSnapshotMapper.map($0, serverId: selection.serverId) }
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.apply(state, generation: generation)
            }
        }
    }

    /// Publishes metadata immediately and lets artwork catch up, so the Now Playing card appears
    /// without waiting on a download.
    ///
    /// Artwork already in the cache is attached to the very first publish rather than arriving in a
    /// second one. The system asks for an image once per content identity, so a card published
    /// without artwork and corrected a moment later just stays blank.
    private func apply(_ state: RemoteMediaEntityState?, generation: Int) {
        guard let state else {
            publish(nil)
            return
        }
        // The key is attached before the image exists. The system asks for artwork once per content
        // identity, so publishing without it and correcting a moment later leaves the card blank
        // forever; the extension's provider waits for preparation instead.
        let desiredKey = artworkKey(for: state)
        let descriptor = desiredKey.map(RemoteMediaArtworkDescriptor.init(cacheKey:))
        let isReady = descriptor.map(RemoteMediaArtworkCache.contains) ?? false
        publish(state.snapshot.withArtwork(descriptor))

        // Preparation is keyed on artwork identity, not on every state delivery: a playing player
        // sends many, and restarting the download on each one means it never finishes.
        guard let desiredKey, !isReady else {
            artworkKey = desiredKey
            return
        }
        guard desiredKey != artworkKey || artworkTask == nil else { return }
        artworkKey = desiredKey
        artworkTask?.cancel()
        artworkTask = Task { [weak self, artwork] in
            let prepared = await artwork.descriptor(for: state)
            await MainActor.run {
                guard let self, self.generation == generation, self.artworkKey == desiredKey else { return }
                self.artworkTask = nil
                guard prepared == nil else { return }
                // Preparation failed, so withdraw the promise rather than leaving the extension
                // waiting on a file that will never appear.
                Current.Log.info("Remote media artwork unavailable; withdrawing its key")
                guard let current = self.snapshot, current.trackId == state.snapshot.trackId else { return }
                self.artworkKey = nil
                self.publish(current.withArtwork(nil))
            }
        }
    }

    /// The cache key this state's artwork would have, or `nil` when there is nothing to show.
    private func artworkKey(for state: RemoteMediaEntityState) -> String? {
        guard state.snapshot.hasMeaningfulMedia, let source = state.artworkSource, !source.isEmpty else { return nil }
        return RemoteMediaArtworkCache.key(
            sessionId: state.snapshot.id,
            trackId: state.snapshot.trackId,
            source: source
        )
    }

    /// Publishes only a genuine change, so the extension is not handed the same session repeatedly.
    private func publish(_ snapshot: RemoteMediaSnapshot?) {
        guard self.snapshot != snapshot || !hasPublished else { return }
        hasPublished = true
        self.snapshot = snapshot
        publisher.publish(snapshot)
    }

    nonisolated func serversDidChange(_ serverManager: ServerManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }
}
#endif
