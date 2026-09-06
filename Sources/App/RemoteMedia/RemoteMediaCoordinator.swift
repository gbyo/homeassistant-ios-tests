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
    private var subscription: HACancellable?
    private var foregroundObserver: NSObjectProtocol?
    private var generation = 0
    private var hasPublished = false

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
        self.selection = selection
        publisher.publish(nil)
        refresh()
    }

    func refresh() {
        generation += 1
        let generation = generation
        subscription?.cancel()
        subscription = nil
        snapshot = nil
        hasPublished = false
        error = nil
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
            let snapshot = states[selection.entityId]
                .flatMap { RemoteMediaSnapshotMapper.map($0, serverId: selection.serverId) }
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                // The first delivery always publishes, so a session left behind by a previous launch
                // is ended even when the entity is gone and the snapshot has not changed.
                guard self.snapshot != snapshot || !self.hasPublished else { return }
                self.hasPublished = true
                self.snapshot = snapshot
                self.publisher.publish(snapshot)
            }
        }
    }

    nonisolated func serversDidChange(_ serverManager: ServerManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }
}
#endif
