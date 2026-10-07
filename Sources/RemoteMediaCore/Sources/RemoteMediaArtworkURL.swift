import Foundation

/// An artwork URL that is safe to put in a snapshot: absolute HTTPS, a plain host name or IP literal,
/// and nothing that could carry a credential — no user or password, no query and no fragment.
///
/// The app never produces one: it can fetch any `entity_picture` through its own authenticated
/// connection and publish a `cached` descriptor instead. This exists for a server pushing a snapshot
/// while the app is not running, when the only cover the RemoteMedia extension can show is one it
/// can fetch with no credentials at all.
///
/// The checks are about confidentiality, because a snapshot leaves the app through Apple's Remote
/// Media infrastructure. Home Assistant's `/api/media_player_proxy/...` paths carry a signed token in
/// their query, which is refused; a token hidden in an ordinary-looking path cannot be recognized by
/// anyone, so publishing such a URL is the server vouching that the image is public.
///
/// The host must be a DNS name (letters, digits, `-` and `.`, with internationalized names in their
/// ASCII form) or a bracketed IPv6 literal. That is a syntax rule, not a destination one: it refuses
/// hosts such as `cdn.example.com%40evil.com`, which Foundation decodes to `cdn.example.com@evil.com`
/// and which anything rebuilding a URL from that host would read as a user and a different host.
///
/// Whether the host is somewhere the device should be sent — a public address rather than loopback,
/// link-local or a private network — is deliberately not decided here. A name only becomes an address
/// when it is resolved, so that check belongs to whatever fetches the image, at the time it fetches.
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
