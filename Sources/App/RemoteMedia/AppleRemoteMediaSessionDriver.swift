#if !targetEnvironment(macCatalyst)
import NowPlaying
import Shared
import UIKit

@available(iOS 27.0, *)
@MainActor
final class AppleRemoteMediaSessionDriver: RemoteMediaSessionDriver {
    func publish(_ snapshot: RemoteMediaSnapshot?) async throws {
        let sessions = try await RemoteMediaSession<Shared.RemoteMediaSessionAttributes>.sessions()
        let active = snapshot
        // Fetch from the system to recover sessions surviving an app relaunch.
        try await Self.endStaleSessions(
            sessions.map { session in (id: session.id, end: { try await session.end() }) },
            activeId: active?.id
        )
        guard let active else { return }
        let attributes = Shared.RemoteMediaSessionAttributes(
            snapshot: active,
            // Read here rather than carried through the snapshot: the lifetime belongs to the
            // Follow relationship, not to any one piece of playback state. It travels in the
            // attributes because a cold-launched extension has nothing else to learn it from.
            lifetime: Current.settingsStore.remoteMediaFollowLifetime
        )
        let session: RemoteMediaSession<Shared.RemoteMediaSessionAttributes>
        if let existing = sessions.first(where: { $0.id == active.id }) {
            session = existing
            try await session.update(attributes)
            Current.Log.verbose("Remote media session updated: \(active.state)")
        } else {
            session = try await .start(attributes: attributes)
            Current.Log.info("Remote media session started")
        }
        if UIApplication.shared.applicationState == .active, !session.isSystemPrimary {
            try await session.requestToBecomeSystemPrimary()
        }
    }

    static func endStaleSessions(
        _ sessions: [(id: String, end: () async throws -> Void)],
        activeId: String?
    ) async throws {
        for session in sessions where session.id != activeId {
            do {
                try await session.end()
                Current.Log.info("Remote media session ended")
            } catch let error as RemoteMediaSessionError {
                // A stale framework session must not prevent the desired one being published.
                Current.Log.error("Could not end stale remote media session: \(error)")
            }
        }
    }
}
#endif
