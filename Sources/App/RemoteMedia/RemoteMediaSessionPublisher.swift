#if !targetEnvironment(macCatalyst)
import Shared

/// Serializes framework calls. An update arriving during start/end is reconciled immediately after it.
@available(iOS 27.0, *)
@MainActor
final class RemoteMediaSessionPublisher {
    private let driver: any RemoteMediaSessionDriver
    private var desired: RemoteMediaSnapshot?
    private var revision = 0
    private var task: Task<Void, Never>?
    var onError: ((Error?) -> Void)?

    init(driver: any RemoteMediaSessionDriver) { self.driver = driver }

    func publish(_ snapshot: RemoteMediaSnapshot?) {
        desired = snapshot?.isActive == true ? snapshot : nil
        revision += 1
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while true {
                let revision = revision
                do {
                    try await driver.publish(desired)
                    onError?(nil)
                } catch {
                    Current.Log.error("Remote media session lifecycle failed: \(error)")
                    onError?(error)
                }
                if revision == self.revision { break }
            }
            task = nil
        }
    }

    func waitForPendingUpdates() async { await task?.value }
}
#endif
