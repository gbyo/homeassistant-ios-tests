import Foundation

/// Posts one `mobile_app` webhook `call_service` request per user action.
///
/// Deliberately the whole networking story for the extension: no HAKit, no WebSocket, no OAuth
/// token and no entity-state round trip, because the process has a 6144 KB ledger. The host app
/// prepared the candidate URLs and the secret, so this only picks, seals and sends.
public struct RemoteMediaWebhookClient: Sendable {
    public enum ClientError: Error, Equatable {
        case noTransportContext
        case noUsableURL
        case unacceptableStatus(code: Int)
        case invalidResponse
    }

    /// How long a system media control may wait before the command reports failure.
    public static let timeout: TimeInterval = 10

    public typealias Perform = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let perform: Perform
    private let transport: RemoteMediaWebhookTransport?

    /// Uses one session for a command and its read-backs; call `endBurst()` when they are done.
    public init() {
        let transport = RemoteMediaWebhookTransport()
        self.transport = transport
        self.perform = { try await transport.perform($0) }
    }

    public init(perform: @escaping Perform) {
        self.transport = nil
        self.perform = perform
    }

    /// Releases the connection this command's requests shared.
    public func endBurst() {
        transport?.invalidate()
    }

    public func send(
        _ command: RemoteMediaCommand,
        value: Double? = nil,
        selection: RemoteMediaSelection,
        context: RemoteMediaTransportContext
    ) async throws {
        // An old system callback must never reach a player the user has stopped following.
        guard context.selection == selection else { throw RemoteMediaError.noLongerFollowing }
        guard !context.webhookURLs.isEmpty else { throw ClientError.noUsableURL }

        let call = try RemoteMediaServiceCall(command: command, entityId: selection.entityId, value: value)
        let body = try Self.body(for: call, secret: context.secret)

        var lastError: Error = ClientError.noUsableURL
        for (index, url) in context.webhookURLs.enumerated() {
            do {
                try await post(body, to: url)
                RemoteMediaLog.logger.info(
                    "command sent: \(call.service, privacy: .public) candidate=\(index, privacy: .public)"
                )
                return
            } catch {
                lastError = error
                guard Self.shouldTryNextCandidate(after: error) else { throw error }
                RemoteMediaLog.logger.debug(
                    "webhook candidate \(index, privacy: .public) failed, trying next"
                )
            }
        }
        throw lastError
    }

    /// Reads the followed player's state back through `render_template`.
    ///
    /// The same encrypted webhook the commands use — no bearer token, no WebSocket, no entity-state
    /// API of our own — because the extension has a 6144 KB ledger to stay inside.
    public func readState(
        selection: RemoteMediaSelection,
        context: RemoteMediaTransportContext
    ) async throws -> RemoteMediaStateReadback {
        guard context.selection == selection else { throw RemoteMediaError.noLongerFollowing }
        guard let url = context.webhookURLs.first else { throw ClientError.noUsableURL }

        let data: [String: Any] = [
            RemoteMediaStateTemplate.resultKey: [
                "template": RemoteMediaStateTemplate.template(entityId: selection.entityId),
            ],
        ]
        let response = try await post(
            Self.body(type: "render_template", data: data, secret: context.secret),
            to: url
        )
        let object = try Self.responseObject(from: response, secret: context.secret)
        guard let dictionary = object as? [String: Any],
              let rendered = dictionary[RemoteMediaStateTemplate.resultKey] else {
            return .unreadable
        }
        return RemoteMediaStateTemplate.readback(from: rendered, serverId: selection.serverId)
    }

    /// The request body: sealed when the registration has a secret, plain otherwise. Matches what
    /// `WatchWebhookClient` and `WebhookRequest` send, so HA Core sees one wire format.
    static func body(for call: RemoteMediaServiceCall, secret: [UInt8]?) throws -> [String: Any] {
        try body(type: "call_service", data: call.webhookData, secret: secret)
    }

    static func body(type: String, data: Any, secret: [UInt8]?) throws -> [String: Any] {
        var body: [String: Any] = ["type": type]
        if let secret {
            body["encrypted"] = true
            body["encrypted_data"] = try WebhookSecretBox.seal(data, secret: secret)
        } else {
            body["data"] = data
        }
        return body
    }

    /// The response's JSON, unsealed when the server encrypted it.
    static func responseObject(from data: Data, secret: [UInt8]?) throws -> Any {
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        guard let dictionary = object as? [String: Any],
              let encoded = dictionary["encrypted_data"] as? String else { return object }
        guard let secret else { return object }
        return try WebhookSecretBox.open(encoded, secret: secret)
    }

    /// Only a candidate that failed in a way the next endpoint could plausibly survive is retried,
    /// so a rejected payload does not get replayed against every URL.
    static func shouldTryNextCandidate(after error: Error) -> Bool {
        switch error {
        case let ClientError.unacceptableStatus(code):
            // A cloudhook that is temporarily down, or an endpoint this route cannot reach.
            return code == 502 || code == 503 || code == 504
        case is URLError:
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func post(_ body: [String: Any], to url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, response) = try await perform(request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ClientError.unacceptableStatus(code: response.statusCode)
        }
        return data
    }
}
