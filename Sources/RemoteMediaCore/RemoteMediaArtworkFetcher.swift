import Foundation

/// Fetches album art from a credential-free absolute HTTPS source.
///
/// Exists because the host app cannot do it when it is not running. A push from Home Assistant can
/// cold-launch this extension with a track it has never seen, and the artwork for it has to come
/// from somewhere; the alternative the extension used to take — waiting for the host app to prepare
/// a file — cannot terminate when there is no host app, and `mediaremoted` kills a session that
/// holds a callback open.
///
/// Nothing here authenticates, and nothing here may. The session runs with a 6144 KB ledger and no
/// Companion dependency graph, so it has no Home Assistant credentials to send and must not acquire
/// any: the URL it is given came over the air, and a request that carried a token to whatever host
/// that names would be handing it out.
public enum RemoteMediaArtworkFetcher {
    /// Enough for a comfortably large album cover. A source claiming more than this is refused
    /// before it is read, so a hostile or broken origin cannot spend the extension's ledger.
    public static let maximumBytes = 2 * 1024 * 1024
    /// Well inside the watchdog. Artwork is optional; being late is worse than being absent.
    public static let timeout: TimeInterval = 3

    /// No cookies, no credential store, no cache: nothing this process holds can be attached to a
    /// request whose destination it did not choose.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.allowsCellularAccess = true
        return URLSession(configuration: configuration)
    }()

    /// Whether this is a source the extension may fetch on its own.
    ///
    /// HTTPS only, and no user info: a URL that carries credentials in its authority is not a
    /// public reference, whatever else it looks like.
    public static func isFetchable(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard url.user == nil, url.password == nil else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// What one fetch did, in the terms a device capture is read in.
    ///
    /// The bytes are separate from the description of them on purpose: every outcome, including
    /// every refusal, has something to say, and a fetch that returns nothing is the case most in
    /// need of explaining.
    public struct Outcome: Sendable {
        public let data: Data?
        public let status: Int?
        public let mimeType: String?
        public let byteCount: Int
        public let reason: String

        /// Safe to log: the origin without the path, so a capture says where the image came from
        /// without reproducing a source that may identify what is playing.
        public static func host(of url: URL) -> String { url.host ?? "-" }
    }

    /// The image bytes, or an outcome saying why there are none.
    ///
    /// Never throws: artwork is optional and no failure of it may fail a session.
    public static func fetch(from url: URL) async -> Outcome {
        guard isFetchable(url) else {
            return .init(data: nil, status: nil, mimeType: nil, byteCount: 0, reason: "refused source")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        // Belt and braces: `ephemeral` already holds nothing, and this says so at the request too.
        request.httpShouldHandleCookies = false

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            return .init(data: nil, status: nil, mimeType: nil, byteCount: 0, reason: "unreachable")
        }
        let http = response as? HTTPURLResponse
        let mime = http?.mimeType
        guard let http, http.statusCode == 200 else {
            return .init(
                data: nil, status: http?.statusCode, mimeType: mime, byteCount: 0,
                reason: "status"
            )
        }
        guard let finalURL = response.url, isFetchable(finalURL) else {
            return .init(data: nil, status: 200, mimeType: mime, byteCount: 0, reason: "refused redirect")
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            return .init(data: nil, status: 200, mimeType: mime, byteCount: 0, reason: "too large")
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        do {
            for try await byte in bytes {
                guard data.count < maximumBytes else {
                    return .init(
                        data: nil, status: 200, mimeType: mime,
                        byteCount: maximumBytes + 1, reason: "too large"
                    )
                }
                data.append(byte)
            }
        } catch {
            return .init(
                data: nil, status: 200, mimeType: mime, byteCount: data.count,
                reason: "unreachable"
            )
        }
        guard !data.isEmpty else {
            return .init(data: nil, status: 200, mimeType: mime, byteCount: 0, reason: "empty")
        }
        return .init(data: data, status: 200, mimeType: mime, byteCount: data.count, reason: "ok")
    }

    /// The image bytes, or `nil`. Kept for callers that have nothing to say about a failure.
    public static func data(from url: URL) async -> Data? {
        await fetch(from: url).data
    }
}
