import Foundation
import WebhookCrypto

/// Lightweight encrypted `mobile_app` webhook primitives shared by the app and extension.
public struct RemoteMediaWebhookClient: Sendable {
    public enum ClientError: Error, Equatable {
        case noTransportContext
        case noUsableURL
        case unacceptableStatus(code: Int)
        case invalidResponse
        case unencodablePayload
    }

    public static let timeout: TimeInterval = 10

    public typealias Perform = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let perform: Perform
    private let transport: RemoteMediaWebhookTransport?

    public init() {
        let transport = RemoteMediaWebhookTransport()
        self.transport = transport
        self.perform = { try await transport.perform($0) }
    }

    public init(perform: @escaping Perform) {
        self.transport = nil
        self.perform = perform
    }

    public func endBurst() {
        transport?.invalidate()
    }

    /// Posts an encrypted or plaintext webhook envelope to the first usable route.
    func post(
        type: String,
        data: Any,
        secret: [UInt8]?,
        candidates: [URL],
        describing label: String
    ) async throws -> Data {
        guard !candidates.isEmpty else { throw ClientError.noUsableURL }
        let body = try Self.body(type: type, data: data, secret: secret)
        var lastError: Error = ClientError.noUsableURL
        for (index, url) in candidates.enumerated() {
            do {
                let data = try await post(body, to: url)
                RemoteMediaLog.logger.info(
                    "sent \(label, privacy: .public) candidate=\(index, privacy: .public)"
                )
                return data
            } catch {
                lastError = error
                guard Self.shouldTryNextCandidate(after: error) else { throw error }
            }
        }
        throw lastError
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

    static func payload(_ value: some Encodable) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw ClientError.unencodablePayload
        }
        return object
    }

    static func responseObject(from data: Data, secret: [UInt8]?) throws -> Any {
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        guard let dictionary = object as? [String: Any],
              let encoded = dictionary["encrypted_data"] as? String else { return object }
        guard let secret else { return object }
        return try WebhookSecretBox.open(encoded, secret: secret)
    }

    private static func shouldTryNextCandidate(after error: Error) -> Bool {
        switch error {
        case let ClientError.unacceptableStatus(code):
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
