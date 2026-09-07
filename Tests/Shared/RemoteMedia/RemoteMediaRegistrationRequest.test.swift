import Foundation
@testable import Shared
import Testing

/// The registration and dismissal as Home Assistant receives them.
///
/// Both go out through the same encrypted `mobile_app` envelope the commands use, and the payload
/// keys are what `homeassistant/components/mobile_app/remote_media/webhook.py` requires, so they
/// are asserted literally rather than through the Swift property names.
struct RemoteMediaRegistrationRequestTests {
    private let selection = RemoteMediaSelection(serverId: "home", entityId: "media_player.speaker")
    private let secret: [UInt8] = Array(repeating: 9, count: 32)

    private func context(secret: [UInt8]? = nil) -> RemoteMediaTransportContext {
        .init(
            selection: selection,
            webhookURLs: [URL(string: "https://example.com/api/webhook/abc")!],
            secret: secret
        )
    }

    private func registration(
        generation: String? = "F1B7D0A2",
        token: String = "0a1b2c3d"
    ) -> RemoteMediaSessionRegistration {
        .init(
            sessionId: selection.id,
            generation: generation,
            entityId: selection.entityId,
            pushToken: token
        )
    }

    private final class Recorder: @unchecked Sendable {
        var requests: [URLRequest] = []
        var status = 200

        var perform: RemoteMediaWebhookClient.Perform {
            { [self] request in
                requests.append(request)
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
                )!
                return (Data(), response)
            }
        }
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let httpBody = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: httpBody)
        return try #require(object as? [String: Any])
    }

    // MARK: - Construction

    /// Home Assistant recovers the followed server from the session identifier and refuses a
    /// registration whose identifier does not describe the entity it names, so the identifier must
    /// be the selection's and never a fresh one.
    @Test func theRegistrationCarriesTheSelectionsOwnIdentifier() {
        let registration = registration()
        #expect(registration.sessionId == selection.id)
        #expect(registration.sessionId == "4:homemedia_player.speaker")
        #expect(registration.entityId == "media_player.speaker")
        #expect(registration.generation == "F1B7D0A2")
        #expect(registration.schemaVersion == 1)
        #expect(RemoteMediaSessionRegistration.currentSchemaVersion == 1)
    }

    /// APNs addresses a token in lowercase hexadecimal, and `RemoteMediaPushToken.hex` is what a
    /// registration is built from rather than any other rendering of the bytes.
    @Test func theTokenIsLowercaseHexadecimal() {
        let token = RemoteMediaPushToken(Data([0x0A, 0xFF, 0x10, 0xBC]))
        #expect(token.hex == "0aff10bc")
        let registration = registration(token: token.hex)
        #expect(registration.pushToken == "0aff10bc")
        #expect(registration.pushToken == registration.pushToken.lowercased())
    }

    // MARK: - Envelope

    @Test func theRegistrationUsesTheEncryptedMobileAppEnvelope() async throws {
        let recorder = Recorder()
        try await RemoteMediaWebhookClient(perform: recorder.perform)
            .register(registration(), context: context(secret: secret))

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.com/api/webhook/abc")
        let body = try body(of: request)
        #expect(body["type"] as? String == "remote_media_session_token")
        #expect(body["encrypted"] as? Bool == true)
        #expect(body["data"] == nil)

        let sealed = try #require(body["encrypted_data"] as? String)
        // The token is the one thing in here that must not travel in the clear.
        #expect(!sealed.contains("0a1b2c3d"))
        let opened = try WebhookSecretBox.open(sealed, secret: secret)
        let payload = try #require(opened as? [String: Any])
        #expect(Set(payload.keys) == [
            "session_id",
            "generation",
            "entity_id",
            "push_token",
            "schema_version",
        ])
        #expect(payload["session_id"] as? String == "4:homemedia_player.speaker")
        #expect(payload["generation"] as? String == "F1B7D0A2")
        #expect(payload["entity_id"] as? String == "media_player.speaker")
        #expect(payload["push_token"] as? String == "0a1b2c3d")
        #expect(payload["schema_version"] as? Int == 1)
    }

    @Test func theDismissalUsesTheEncryptedMobileAppEnvelope() async throws {
        let recorder = Recorder()
        try await RemoteMediaWebhookClient(perform: recorder.perform).dismiss(
            .init(sessionId: selection.id, generation: "F1B7D0A2"),
            context: context(secret: secret)
        )

        let body = try body(of: #require(recorder.requests.first))
        #expect(body["type"] as? String == "remote_media_session_dismissed")
        #expect(body["encrypted"] as? Bool == true)
        let sealed = try #require(body["encrypted_data"] as? String)
        let opened = try WebhookSecretBox.open(sealed, secret: secret)
        let payload = try #require(opened as? [String: Any])
        // Nothing else: a dismissal names a relationship, it does not describe one.
        #expect(Set(payload.keys) == ["session_id", "generation"])
        #expect(payload["session_id"] as? String == "4:homemedia_player.speaker")
        #expect(payload["generation"] as? String == "F1B7D0A2")
    }

    /// A registration whose lifetime has no generation omits the key rather than sending null;
    /// Home Assistant treats it as optional either way.
    @Test func aLifetimeWithoutAGenerationOmitsTheKey() async throws {
        let recorder = Recorder()
        try await RemoteMediaWebhookClient(perform: recorder.perform)
            .register(registration(generation: nil), context: context())

        let body = try body(of: #require(recorder.requests.first))
        let payload = try #require(body["data"] as? [String: Any])
        #expect(payload["generation"] == nil)
        #expect(payload["session_id"] as? String == "4:homemedia_player.speaker")
    }

    /// The registration goes out over the routes the commands already use, in the same order, and
    /// carries nothing about how the server should reach APNs.
    @Test func theClientNamesNothingAboutApns() async throws {
        let recorder = Recorder()
        let context = RemoteMediaTransportContext(
            selection: selection,
            webhookURLs: [
                URL(string: "https://cloud.example.com/hook")!,
                URL(string: "https://external.example.com/api/webhook/abc")!,
            ],
            secret: nil
        )
        try await RemoteMediaWebhookClient(perform: recorder.perform)
            .register(registration(), context: context)

        let request = try #require(recorder.requests.first)
        #expect(recorder.requests.count == 1)
        #expect(request.url?.host == "cloud.example.com")
        let httpBody = try #require(request.httpBody)
        let raw = try #require(String(data: httpBody, encoding: .utf8))
        for forbidden in ["push.apple.com", "apns", "topic", "team", "key_id"] {
            #expect(!raw.lowercased().contains(forbidden))
        }
        #expect(request.allHTTPHeaderFields?["apns-topic"] == nil)
        #expect(request.allHTTPHeaderFields?["apns-push-type"] == nil)
    }

    /// The same protection the commands have. A context belonging to another player would
    /// authenticate the request as that relationship.
    @Test func aContextForAnotherPlayerCannotRegisterOrDismiss() async {
        let recorder = Recorder()
        let other = RemoteMediaTransportContext(
            selection: .init(serverId: "home", entityId: "media_player.other"),
            webhookURLs: [URL(string: "https://example.com/api/webhook/abc")!],
            secret: nil
        )
        await #expect(throws: RemoteMediaError.noLongerFollowing) {
            try await RemoteMediaWebhookClient(perform: recorder.perform)
                .register(registration(), context: other)
        }
        await #expect(throws: RemoteMediaError.noLongerFollowing) {
            try await RemoteMediaWebhookClient(perform: recorder.perform)
                .dismiss(.init(sessionId: selection.id, generation: "one"), context: other)
        }
        #expect(recorder.requests.isEmpty)
    }
}
