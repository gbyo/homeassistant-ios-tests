import Foundation
@testable import Shared
import Testing

struct RemoteMediaWebhookClientTests {
    private let secret: [UInt8] = Array(repeating: 7, count: 32)

    private final class Recorder: @unchecked Sendable {
        var requests: [URLRequest] = []
        var statuses: [Int]

        init(statuses: [Int]) {
            self.statuses = statuses
        }

        var perform: RemoteMediaWebhookClient.Perform {
            { [self] request in
                let index = requests.count
                requests.append(request)
                let code = index < statuses.count ? statuses[index] : 200
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil
                )!
                return (Data(), response)
            }
        }
    }

    @Test func plaintextEnvelopeKeepsDataInTheBody() throws {
        let body = try RemoteMediaWebhookClient.body(type: "test", data: ["value": 1], secret: nil)
        #expect(body["type"] as? String == "test")
        #expect(body["data"] != nil)
        #expect(body["encrypted_data"] == nil)
    }

    @Test func secretboxEnvelopeDoesNotExposePlaintext() throws {
        let body = try RemoteMediaWebhookClient.body(
            type: "test",
            data: ["entity_id": "media_player.speaker"],
            secret: secret
        )
        let encoded = try #require(body["encrypted_data"] as? String)
        #expect(body["encrypted"] as? Bool == true)
        #expect(body["data"] == nil)
        #expect(!encoded.contains("media_player.speaker"))
        let opened = try #require(WebhookSecretBox.open(encoded, secret: secret) as? [String: Any])
        #expect(opened["entity_id"] as? String == "media_player.speaker")
    }

    @Test func transportFallsBackAcrossRoutes() async throws {
        let recorder = Recorder(statuses: [503, 200])
        _ = try await RemoteMediaWebhookClient(perform: recorder.perform).post(
            type: "test",
            data: [:],
            secret: nil,
            candidates: [URL(string: "https://a.example/h")!, URL(string: "https://b.example/h")!],
            describing: "test"
        )
        #expect(recorder.requests.count == 2)
    }
}
