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
    private let dismissals: RemoteMediaDismissalSender
    private var subscription: HACancellable?
    private var foregroundObserver: NSObjectProtocol?
    private var generation = 0
    private var hasPublished = false

    convenience init() {
        self.init(publisher: .init(driver: AppleRemoteMediaSessionDriver()))
    }

    init(publisher: RemoteMediaSessionPublisher, dismissals: RemoteMediaDismissalSender = .init()) {
        self.publisher = publisher
        self.dismissals = dismissals
        self.selection = Current.settingsStore.remoteMediaSelection
        publisher.onError = { [weak self] error in
            self?.error = error?.localizedDescription
        }
    }

    func start(deferNetworkingUntilActive: Bool = false) {
        guard foregroundObserver == nil else { return }
        Current.settingsStore.migrateRemoteMediaFollowLifetime()
        Current.servers.add(observer: self)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.reconcileDismissals()
            }
        }
        guard !deferNetworkingUntilActive else { return }
        refresh()
        reconcileDismissals()
    }

    private func reconcileDismissals() {
        guard !Current.settingsStore.remoteMediaPendingDismissals.isEmpty else { return }
        Task { await RemoteMediaDismissalReconciler.reconcile() }
    }

    func follow(_ selection: RemoteMediaSelection?) {
        if let selection, !RemoteMediaEntityId.isValid(selection.entityId) { return }
        let ending = RemoteMediaFollowEnd.capture(
            selection: self.selection,
            lifetime: Current.settingsStore.remoteMediaFollowLifetime,
            context: RemoteMediaTransportStore.load()
        )
        if let ending {
            Current.settingsStore.addRemoteMediaPendingDismissal(ending.pending)
        }
        Current.settingsStore.startRemoteMediaFollowLifetime(following: selection)
        self.selection = Current.settingsStore.remoteMediaSelection
        publisher.publish(nil)
        if selection == nil {
            RemoteMediaTransportStore.clear()
        }
        refresh()
        guard let ending else { return }
        Task { [dismissals] in
            if await dismissals.send(ending) {
                Current.settingsStore.removeRemoteMediaPendingDismissal(ending.pending)
            }
        }
    }

    func refresh() {
        if Current.settingsStore.adoptRemoteMediaSelectionUpdate() {
            selection = Current.settingsStore.remoteMediaSelection
        }
        generation += 1
        let generation = generation
        subscription?.cancel()
        subscription = nil
        snapshot = nil
        hasPublished = false
        error = nil
        RemoteMediaTransportContextWriter.update(
            for: selection,
            lifetime: Current.settingsStore.remoteMediaFollowLifetime
        )
        if selection == nil {
            RemoteMediaReofferSignal.clear()
        } else {
            RemoteMediaReofferSignal.request()
        }
        guard let selection,
              let server = Current.servers.server(forServerIdentifier: selection.serverId),
              let api = Current.api(for: server) else {
            publisher.publish(nil)
            return
        }
        var filter: [String: Any] = [:]
        if server.info.version > .canSubscribeEntitiesChangesWithFilter {
            filter = ["include": ["entities": [selection.entityId]]]
        }
        api.connectWebSocketIfNeeded()
        subscription = api.connection.caches.states(filter).subscribe { [weak self] _, states in
            let state = states[selection.entityId]
                .flatMap { RemoteMediaSnapshotMapper.map($0, serverId: selection.serverId) }
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.apply(state)
            }
        }
    }

    private func apply(_ state: RemoteMediaEntityState?) {
        guard let state else {
            publish(nil)
            return
        }
        publish(RemoteMediaSnapshotReducer.reduce(previous: snapshot, incoming: state.snapshot))
    }

    private func publish(_ snapshot: RemoteMediaSnapshot?) {
        guard self.snapshot != snapshot || !hasPublished else { return }
        hasPublished = true
        self.snapshot = snapshot
        publisher.publish(snapshot)
    }

    nonisolated func serversDidChange(_ serverManager: ServerManager) {
        Task { @MainActor [weak self] in
            self?.refresh()
            self?.reconcileDismissals()
        }
    }
}
#endif
