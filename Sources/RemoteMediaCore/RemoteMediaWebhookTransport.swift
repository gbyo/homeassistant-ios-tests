import Foundation

/// One `URLSession` for the length of a command and its read-backs, then released.
///
/// Both extremes were measured on device against the extension's 6144 KB ledger. A session kept for
/// the life of the process took the first POST from 3297 KB to 5681 KB and never gave it back. A
/// session per request instead paid for five TLS handshakes and trust evaluations per user action —
/// one command plus up to four read-backs — and still climbed.
///
/// A burst is the natural scope: the command and everything it waits for share one connection, and
/// the process holds nothing between them.
public final class RemoteMediaWebhookTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?

    public init() {}

    public func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = currentSession()
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RemoteMediaWebhookClient.ClientError.invalidResponse
        }
        return (data, response)
    }

    /// Ends the burst. Safe to call more than once, and a later request simply starts a new one.
    public func invalidate() {
        lock.lock()
        let session = session
        self.session = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
    }

    private func currentSession() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = RemoteMediaWebhookClient.timeout
        configuration.waitsForConnectivity = false
        // An ephemeral session still keeps an in-memory response cache, which is dead weight in a
        // process that never reads a response twice.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        self.session = session
        return session
    }
}
