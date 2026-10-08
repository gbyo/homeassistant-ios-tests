import Foundation

/// An artwork URL that is safe to put in a snapshot: absolute HTTPS, a plain host name or IP literal,
/// and nothing that could carry a credential (no user or password, no query, no fragment).
///
/// The app never produces one, since it can fetch any `entity_picture` itself and publish a `cached`
/// descriptor. This is for a server pushing a snapshot while the app is not running, when the only cover
/// the extension can show is one it can fetch with no credentials. Home Assistant's
/// `/api/media_player_proxy/...` paths carry a signed token in their query and are refused; a token
/// hidden in an ordinary-looking path cannot be recognized, so publishing such a URL is the server
/// vouching that the image is public.
///
/// The host must be a DNS name (ASCII letters, digits, `-` and `.`) or a bracketed IPv6 literal. That is
/// a syntax rule, not a destination one: it refuses hosts such as `cdn.example.com%40evil.com`, which
/// Foundation decodes to `cdn.example.com@evil.com`. Whether a host is somewhere the device should be
/// sent (public rather than loopback or private) is left to whatever fetches the image, since a name
/// only becomes an address when it is resolved.
public struct RemoteMediaArtworkURL: Equatable, Sendable, Codable {
    public let url: URL

    init?(_ url: URL) {
        guard url.baseURL == nil,
              url.scheme?.lowercased() == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.encodedHost, Self.isPlainHost(host),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        self.url = url
    }

    private static func isPlainHost(_ host: String) -> Bool {
        if host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 {
            return host.dropFirst().dropLast().allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }
        return !host.isEmpty && host.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == ".")
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let artworkURL = try URL(string: container.decode(String.self)).flatMap(Self.init) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Artwork URLs must be credential-free absolute HTTPS URLs"
            )
        }
        self = artworkURL
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url.absoluteString)
    }
}
