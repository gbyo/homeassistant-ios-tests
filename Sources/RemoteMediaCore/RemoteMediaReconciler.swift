import Foundation

/// Performs one bounded fallback read after a command.
///
/// `call_service` returning 200 only means Home Assistant accepted it; an Echo's state can lag by a
/// second or more. Without this the extension sends Next, the Echo changes track, and the Now
/// Playing card keeps showing the old song until the containing app happens to be opened.
///
/// Home Assistant's `nowplaying` APNs update is authoritative and works while the app is closed.
/// This read is only a latency fallback for a process that happens to remain alive.
public struct RemoteMediaReconciler: Sendable {
    /// When to look, measured from the command completing. Short enough to feel immediate, spread
    /// wide enough to catch a cloud integration that answers late.
    public static let attemptDelays: [Duration] = [.milliseconds(750)]

    public typealias Fetch = @Sendable () async throws -> RemoteMediaStateReadback

    private let fetch: Fetch
    private let delays: [Duration]

    public init(delays: [Duration] = RemoteMediaReconciler.attemptDelays, fetch: @escaping Fetch) {
        self.delays = delays
        self.fetch = fetch
    }

    /// The last state read, whether or not it settled — a late-but-real report still beats showing
    /// the previous track. `nil` when nothing could be read at all.
    public func reconcile(
        until condition: RemoteMediaSettleCondition,
        onUpdate: @Sendable (RemoteMediaStateReadback) async -> Void
    ) async {
        for delay in delays {
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }

            let readback: RemoteMediaStateReadback
            do {
                readback = try await fetch()
            } catch {
                RemoteMediaLog.logger.debug("reconcile fallback fetch failed")
                continue
            }
            if Task.isCancelled { return }

            switch readback {
            case let .entity(state):
                await onUpdate(readback)
                if condition.isSettled(state.snapshot) { return }
            case .missing:
                // Terminal: the entity is gone, so there is nothing left to settle.
                await onUpdate(readback)
                return
            case .unreadable:
                continue
            }
        }
    }
}
