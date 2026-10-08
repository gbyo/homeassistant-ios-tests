import CryptoKit
import Foundation

/// A SHA-256 digest in lowercase hexadecimal: the only form an identifier takes on the wire.
///
/// Integrations put whatever they like in values such as `media_content_id`, including stream URLs
/// with signed query strings. Remote Now Playing needs to know whether two reports name the same
/// thing, never what the thing is, and a snapshot is published outside the app, so it carries a
/// digest and the original stays on the server. Decoding accepts exactly 64 lowercase hex
/// characters, so a payload cannot put a raw value back in a field meant to hold one of these.
///
/// A server reproduces `init(hashing:)` as `hashlib.sha256(value.encode()).hexdigest()`: both hash the
/// string's UTF-8 bytes exactly as received, with no Unicode normalization.
public struct RemoteMediaDigest: Hashable, Sendable, Codable {
    /// 64 lowercase hexadecimal characters.
    public let hexString: String

    /// The digest of `value`'s UTF-8 bytes.
    init(hashing value: String) {
        self.hexString = SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// The digest of several fields that must not run together: each is written as its UTF-8 byte
    /// count, a colon and the value, and a missing one as `-`, so no two lists share a preimage.
    init(hashingFields fields: [String?]) {
        self.init(hashing: fields.map { $0.map { "\($0.utf8.count):\($0)" } ?? "-" }.joined())
    }

    init?(hexString: String) {
        let isDigest = hexString.utf8.count == 64 && hexString.utf8.allSatisfy { byte in
            (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a") ... UInt8(ascii: "f")).contains(byte)
        }
        guard isDigest else { return nil }
        self.hexString = hexString
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let digest = try Self(hexString: container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a lowercase hexadecimal SHA-256 digest"
            )
        }
        self = digest
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}
