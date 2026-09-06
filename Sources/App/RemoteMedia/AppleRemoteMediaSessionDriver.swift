#if !targetEnvironment(macCatalyst)
import ExtensionFoundation
import NowPlaying
import Shared
import UIKit

@available(iOS 27.0, *)
@MainActor
final class AppleRemoteMediaSessionDriver: RemoteMediaSessionDriver {
    // TEMPORARY DIAGNOSTIC — NOT FOR COMMIT.
    // The production code catches every framework call in one place, which only told us
    // "internalFailure". Everything tagged [RM-DIAG] exists to name the failing call and to say
    // whether the system can see the Remote Media extension at all. Revert with:
    //   git checkout -- Sources/App/RemoteMedia/AppleRemoteMediaSessionDriver.swift
    private var didProbeExtensions = false

    func publish(_ snapshot: RemoteMediaSnapshot?) async throws {
        await probeExtensionsOnce()
        let sessions = try await step("sessions()") {
            try await RemoteMediaSession<Shared.RemoteMediaSessionAttributes>.sessions()
        }
        Current.Log.info("[RM-DIAG] existing sessions: \(sessions.map(\.id))")
        let active = snapshot.flatMap { $0.isActive ? $0 : nil }
        Current.Log.info("[RM-DIAG] desired: \(active?.id ?? "none") state=\(active?.state ?? "nil")")
        // Fetch from the system to recover sessions surviving an app relaunch.
        for session in sessions where session.id != active?.id {
            try await step("end()") { try await session.end() }
            Current.Log.info("Remote media session ended")
        }
        guard let active else { return }
        let attributes = Shared.RemoteMediaSessionAttributes(snapshot: active)
        let encodedSize = (try? JSONEncoder().encode(attributes).count) ?? -1
        Current.Log.info("[RM-DIAG] attributes id=\(attributes.id) encodes to \(encodedSize) bytes")
        let session: RemoteMediaSession<Shared.RemoteMediaSessionAttributes>
        if let existing = sessions.first(where: { $0.id == active.id }) {
            session = existing
            try await step("update()") { try await session.update(attributes) }
            Current.Log.verbose("Remote media session updated: \(active.state)")
        } else {
            session = try await step("start()") {
                try await RemoteMediaSession<Shared.RemoteMediaSessionAttributes>.start(attributes: attributes)
            }
            Current.Log.info("Remote media session started")
        }
        let applicationState = UIApplication.shared.applicationState
        Current.Log.info(
            "[RM-DIAG] appState=\(applicationState.rawValue) isSystemPrimary=\(session.isSystemPrimary)"
        )
        if applicationState == .active, !session.isSystemPrimary {
            try await step("requestToBecomeSystemPrimary()") {
                try await session.requestToBecomeSystemPrimary()
            }
        }
    }

    /// Names the call that threw, and prints the error twice: the short description the production
    /// code logs, and the reflected form, which carries the associated values.
    private func step<T>(_ name: String, _ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            Current.Log.info("[RM-DIAG] \(name) ok")
            return result
        } catch {
            Current.Log.error("[RM-DIAG] \(name) FAILED: \(error) — \(String(reflecting: error))")
            throw error
        }
    }

    /// Asks ExtensionFoundation what it can see for the remote-media extension point. Zero
    /// identities means the system never found the embedded appex, which would explain a start
    /// that fails with nothing more specific than `internalFailure`.
    private func probeExtensionsOnce() async {
        guard !didProbeExtensions else { return }
        didProbeExtensions = true
        do {
            let point = try AppExtensionPoint(identifier: "com.apple.nowplaying.remote-media")
            let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: point)
            let state = monitor.state
            Current.Log.info(
                "[RM-DIAG] extension point: \(state.identities.count) identities, "
                    + "\(state.unapprovedCount) unapproved, \(state.disabledCount) disabled — "
                    + state.identities.map(\.bundleIdentifier).joined(separator: ", ")
            )
        } catch {
            Current.Log.error("[RM-DIAG] extension probe failed: \(error) — \(String(reflecting: error))")
        }
    }
}
#endif
