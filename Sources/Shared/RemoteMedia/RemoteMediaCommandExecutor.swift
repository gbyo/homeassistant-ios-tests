import Foundation
import HAKit

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
        RemoteMediaLog.logger.info("command execute begin: \(command.rawValue, privacy: .public)")
        do {
            try await withDeadline {
                // An old system callback must never control a previously followed player.
                let selectionIsCurrent = Current.settingsStore.remoteMediaSelection == selection
                RemoteMediaLog.logger.debug(
                    "selection still current: \(selectionIsCurrent ? "yes" : "no", privacy: .public)"
                )
                guard selectionIsCurrent else {
                    throw RemoteMediaError.noLongerFollowing
                }
                let server = Current.servers.server(forServerIdentifier: selection.serverId)
                RemoteMediaLog.logger.debug("server resolved: \(server == nil ? "no" : "yes", privacy: .public)")
                guard let server else {
                    throw RemoteMediaError.noServer
                }
                let api = Current.api(for: server)
                RemoteMediaLog.logger.debug("API resolved: \(api == nil ? "no" : "yes", privacy: .public)")
                if let api {
                    RemoteMediaLog.logger.debug(
                        "connection state: \(String(describing: api.connection.state), privacy: .public)"
                    )
                }
                RemoteMediaLog.logger.debug("entity state fetch begin")
                let entity: HAEntity
                do {
                    entity = try await AppIntentServerAPI.entityState(server: server, entityId: selection.entityId)
                    RemoteMediaLog.logger.debug("entity state fetch success")
                } catch {
                    let diagnostic = "entity state fetch failure type=\(String(reflecting: type(of: error))) " +
                        "description=\(error.localizedDescription)"
                    RemoteMediaLog.logger.error("\(diagnostic, privacy: .public)")
                    throw error
                }
                guard let snapshot = RemoteMediaSnapshotMapper.map(entity, serverId: selection.serverId),
                      snapshot.isActive else { throw RemoteMediaError.unavailable }
                guard snapshot.features.commands.contains(command) else { throw RemoteMediaError.invalidCommand }
                let selectionIsStillCurrent = Current.settingsStore.remoteMediaSelection == selection
                let selectionStatus = selectionIsStillCurrent ? "yes" : "no"
                RemoteMediaLog.logger.debug(
                    "selection still current before service call: \(selectionStatus, privacy: .public)"
                )
                guard selectionIsStillCurrent else {
                    throw RemoteMediaError.noLongerFollowing
                }
                let clampedValue = command == .seek ? value
                    .map { min(snapshot.duration ?? .greatestFiniteMagnitude, $0) } : value
                RemoteMediaLog.logger.info(
                    "service call begin: media_player.\(command.service, privacy: .public)"
                )
                do {
                    _ = try await AppIntentServerAPI.callAction(
                        server: server,
                        domain: "media_player",
                        service: command.service,
                        data: command.serviceData(entityId: selection.entityId, value: clampedValue),
                        returnResponse: false
                    )
                    RemoteMediaLog.logger.info(
                        "service call success: media_player.\(command.service, privacy: .public)"
                    )
                } catch {
                    let diagnostic = "service call failure: media_player.\(command.service) " +
                        "type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)"
                    RemoteMediaLog.logger.error("\(diagnostic, privacy: .public)")
                    throw error
                }
            }
            RemoteMediaLog.logger.info("command execute completed: \(command.rawValue, privacy: .public)")
        } catch {
            let diagnostic = "command execute failed: \(command.rawValue) " +
                "type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)"
            RemoteMediaLog.logger.error("\(diagnostic, privacy: .public)")
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
