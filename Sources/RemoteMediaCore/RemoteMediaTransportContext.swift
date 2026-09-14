import Foundation

/// Everything the extension needs to issue one `mobile_app` webhook command, and nothing more.
///
/// Kept out of `RemoteMediaSessionAttributes` on purpose: attributes travel through Apple's
/// RemoteMedia infrastructure, while this carries the webhook secret and so lives in the shared
/// Keychain instead. See `RemoteMediaTransportStore`.
public struct RemoteMediaTransportContext: Codable, Equatable, Sendable {
    /// The followed player. A command whose selection no longer matches is refused, so a stale
    /// system callback cannot control a player the user has since stopped following.
    public let selection: RemoteMediaSelection
    /// The Follow relationship this credential was issued for. Optional only so an older
    /// development build's stored context decodes; callers must require a match and therefore
    /// treat a missing value as unauthorized.
    public let lifetime: RemoteMediaFollowLifetime?
    /// Webhook endpoints in the order they should be tried: cloudhook, external, internal.
    public let webhookURLs: [URL]
    /// The secretbox key, already derived for the server's version by the host app. `nil` when the
    /// registration legitimately has no secret, in which case the payload is sent in plaintext.
    public let secret: [UInt8]?

    public init(
        selection: RemoteMediaSelection,
        lifetime: RemoteMediaFollowLifetime? = nil,
        webhookURLs: [URL],
        secret: [UInt8]?
    ) {
        self.selection = selection
        self.lifetime = lifetime
        self.webhookURLs = webhookURLs
        self.secret = secret
    }
}
