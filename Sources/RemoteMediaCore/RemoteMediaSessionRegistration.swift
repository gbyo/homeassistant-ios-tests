import Foundation

/// What the phone tells Home Assistant so the server can push this session's Now Playing updates.
///
/// The token is per-session and lives only as long as the Follow relationship does, so it is sent
/// with the identity the server needs to invalidate it again: the session it belongs to, and the
/// Follow lifetime that minted it. Nothing here is secret — the transport that carries it is the
/// existing encrypted `mobile_app` webhook, and the webhook secret never travels the other way,
/// through the RemoteMedia attributes.
///
/// The APNs environment is deliberately not described here, and no client code should assume one.
/// Measured on iOS 27.0 (2026-09-06): the session update token from a **development**-signed build,
/// with `aps-environment = development` in both the app and the extension, is rejected by sandbox
/// APNs as `BadDeviceToken` and accepted by **production** APNs. That is beta behaviour Apple may
/// change before release — and App Store builds reach production APNs anyway — so the environment
/// belongs in the sender's configuration, not in this contract.
public struct RemoteMediaSessionRegistration: Codable, Equatable, Sendable {
    public let sessionId: String
    /// Which Follow lifetime this token belongs to. See `RemoteMediaRegistrationLedger`.
    public let generation: String?
    public let entityId: String
    /// The APNs update token, lowercase hexadecimal.
    public let pushToken: String
    public let schemaVersion: Int

    public static let currentSchemaVersion = 1

    public init(
        sessionId: String,
        generation: String?,
        entityId: String,
        pushToken: String,
        schemaVersion: Int = RemoteMediaSessionRegistration.currentSchemaVersion
    ) {
        self.sessionId = sessionId
        self.generation = generation
        self.entityId = entityId
        self.pushToken = pushToken
        self.schemaVersion = schemaVersion
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case generation
        case entityId = "entity_id"
        case pushToken = "push_token"
        case schemaVersion = "schema_version"
    }
}
