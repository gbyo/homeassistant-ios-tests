import Foundation
import RemoteMediaCore
import Testing

/// The `artwork` object of the wire contract.
struct RemoteMediaArtworkTests {
    static let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    private func decode(_ json: String) throws -> RemoteMediaArtwork {
        try RemoteMediaFixtures.decode(RemoteMediaArtwork.self, json)
    }

    /// Available artwork at `url`, serialized properly so that what fails to decode is the URL and
    /// never the JSON around it.
    private func decode(url: String) throws -> RemoteMediaArtwork {
        let data = try JSONSerialization.data(withJSONObject: ["state": "available", "url": url])
        return try JSONDecoder().decode(RemoteMediaArtwork.self, from: data)
    }

    @Test func absentAndDeferredCarryNothingElse() throws {
        let decodedAbsent = try decode(#"{"state": "absent"}"#)
        let decodedDeferred = try decode(#"{"state": "deferred"}"#)
        #expect(decodedAbsent == .absent)
        #expect(decodedDeferred == .deferred)
        let absent = try RemoteMediaFixtures.jsonObject(RemoteMediaArtwork.absent)
        let deferred = try RemoteMediaFixtures.jsonObject(RemoteMediaArtwork.deferred)
        #expect(RemoteMediaFixtures.isEqual(absent, ["state": "absent"]))
        #expect(RemoteMediaFixtures.isEqual(deferred, ["state": "deferred"]))
    }

    @Test func availableArtworkInTheCache() throws {
        let artwork = try decode(#"{"state": "available", "cacheKey": "\#(Self.digest)"}"#)
        guard case let .available(.cached(key)) = artwork else {
            Issue.record("Expected cached artwork, got \(artwork)")
            return
        }
        #expect(key.hexString == Self.digest)
        let encoded = try RemoteMediaFixtures.jsonObject(artwork)
        #expect(RemoteMediaFixtures.isEqual(encoded, ["state": "available", "cacheKey": Self.digest]))
    }

    /// Unusual but legitimate forms, each encoded back exactly as received: percent-encoded characters
    /// in the path stay encoded, so `%3F`, `%40` and `%23` never turn into a query, userinfo or fragment.
    @Test(arguments: [
        "https://cdn.example.com/cover.jpg",
        "https://cdn.example.com:8443/covers/a%20b.jpg",
        "https://cdn.example.com/a%3Ftoken%3Dx.jpg",
        "https://cdn.example.com/a%40b%23c.jpg",
        "https://cdn.example.com/;v=2/cover.jpg",
        "https://xn--bcher-kva.example/cover.jpg",
        "https://[2001:db8::1]:8443/cover.jpg",
        "https://203.0.113.7/cover.jpg",
        "HTTPS://cdn.example.com/cover.jpg",
    ])
    func availableArtworkAtAPublicURL(_ url: String) throws {
        let artwork = try decode(url: url)
        guard case let .available(.remote(artworkURL)) = artwork else {
            Issue.record("Expected remote artwork, got \(artwork)")
            return
        }
        #expect(artworkURL.url.absoluteString == url)
        let encoded = try RemoteMediaFixtures.jsonObject(artwork)
        #expect(RemoteMediaFixtures.isEqual(encoded, ["state": "available", "url": url]))
    }

    /// Whatever a payload says, the only URL that decodes is a credential-free absolute HTTPS one.
    @Test(arguments: [
        // Not HTTPS.
        "http://cdn.example.com/cover.jpg", "ftp://cdn.example.com/cover.jpg", "file:///var/mobile/cover.jpg",
        "javascript:alert(1)", "data:image/png;base64,iVBORw0KGgo=",
        // Not absolute: Home Assistant's own proxy path, and other relative forms.
        "/api/media_player_proxy/media_player.living_room?token=secret", "cover.jpg", "//cdn.example.com/cover.jpg",
        // Credentials in the userinfo, the query or the fragment.
        "https://user:password@cdn.example.com/cover.jpg", "https://user@cdn.example.com/cover.jpg",
        "https://:password@cdn.example.com/cover.jpg", "https://@cdn.example.com/cover.jpg",
        "https://cdn.example.com/cover.jpg?token=secret", "https://cdn.example.com/cover.jpg?",
        "https://cdn.example.com/cover.jpg#access_token=secret",
        // Userinfo however it is spelled, including forms Foundation accepts leniently.
        "https://cdn.example.com:443@evil.example/cover.jpg", "https://evil.example\\@cdn.example.com/cover.jpg",
        "https://user name@cdn.example.com/cover.jpg",
        // A host that decodes to something else.
        "https://cdn.example.com%40evil.example/cover.jpg", "https://cdn%2Eexample.com/cover.jpg",
        // Raw whitespace that Foundation percent-encodes still leaves the query it was hiding.
        "https://cdn.example.com/a b?token=secret", "https://cdn.example.com/a\n?token=secret",
        // No host.
        "https://", "https:///cover.jpg", "https:cover.jpg", "https:\\\\cdn.example.com/cover.jpg",
        // Not a URL.
        "", "not a url",
    ])
    func anUnsafeURLDoesNotDecode(_ url: String) {
        #expect(throws: DecodingError.self) {
            try decode(url: url)
        }
    }

    @Test(arguments: [
        "../../Library/Preferences/secret",
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
        String(RemoteMediaArtworkTests.digest.dropLast()),
        RemoteMediaArtworkTests.digest + "0",
        "zz7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "",
    ])
    func aCacheKeyMustBeADigest(_ key: String) {
        #expect(throws: DecodingError.self) {
            try decode(#"{"state": "available", "cacheKey": "\#(key)"}"#)
        }
    }

    /// Every contradictory combination fails rather than being resolved one way or the other.
    @Test(arguments: [
        #"{"state": "available"}"#,
        #"{"state": "available", "cacheKey": "\#(RemoteMediaArtworkTests.digest)", "url": "https://cdn.example.com/cover.jpg"}"#,
        #"{"state": "absent", "url": "https://cdn.example.com/cover.jpg"}"#,
        #"{"state": "deferred", "cacheKey": "\#(RemoteMediaArtworkTests.digest)"}"#,
        #"{"state": "pending"}"#,
        #"{"url": "https://cdn.example.com/cover.jpg"}"#,
        #"{}"#,
        #""absent""#,
        "null",
    ])
    func contradictoryArtworkDoesNotDecode(_ json: String) {
        #expect(throws: DecodingError.self) {
            try decode(json)
        }
    }
}
