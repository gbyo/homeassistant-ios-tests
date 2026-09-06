import Foundation

public struct RemoteMediaCommandExecutor {
    /// How long a system media control may wait for Home Assistant before the command fails.
    ///
    /// The WebSocket request carries no deadline of its own, so a connection that never comes up
    /// would leave the button the user pressed spinning until the system gave up on the extension.
    /// Cancelling only stops this side of the call: a command that timed out may still reach the
    /// server, exactly like an App Intent that times out waiting for a picker.
    static let timeout: TimeInterval = 10

    public init() {}

    public func execute(
        _ command: RemoteMediaCommand,
        selection: RemoteMediaSelection,
        value: Double? = nil
    ) async throws {
        do {
            try await withDeadline {
                // An old system callback must never control a previously followed player.
                guard Current.settingsStore.remoteMediaSelection == selection else {
                    throw RemoteMediaError.noLongerFollowing
                }
                guard let server = Current.servers.server(forServerIdentifier: selection.serverId) else {
                    throw RemoteMediaError.noServer
                }
                let entity = try await AppIntentServerAPI.entityState(server: server, entityId: selection.entityId)
                guard let snapshot = RemoteMediaSnapshotMapper.map(entity, serverId: selection.serverId),
                      snapshot.isActive else { throw RemoteMediaError.unavailable }
                guard snapshot.features.commands.contains(command) else { throw RemoteMediaError.invalidCommand }
                guard Current.settingsStore.remoteMediaSelection == selection else {
                    throw RemoteMediaError.noLongerFollowing
                }
                let clampedValue = command == .seek ? value
                    .map { min(snapshot.duration ?? .greatestFiniteMagnitude, $0) } : value
                _ = try await AppIntentServerAPI.callAction(
                    server: server,
                    domain: "media_player",
                    service: command.service,
                    data: command.serviceData(entityId: selection.entityId, value: clampedValue),
                    returnResponse: false
                )
            }
            Current.Log.info("Remote media command completed: \(command.rawValue)")
        } catch {
            Current.Log.error("Remote media command \(command.rawValue) failed: \(error)")
            throw error
        }
    }

    private func withDeadline(_ work: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
                throw RemoteMediaError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
