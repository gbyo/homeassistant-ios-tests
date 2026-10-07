import CryptoKit
import Foundation

/// A SHA-256 digest in lowercase hexadecimal: the only form an identifier takes on the wire.
///
/// Integrations put whatever they like in values such as `media_content_id` — stream URLs with
/// signed query strings, local file paths, account-scoped ids. Remote Now Playing needs to know
/// whether two reports name the same thing, never what the thing is, so it carries a digest instead
/// and the original stays on the server. Decoding accepts exactly 64 lowercase hex characters, so a
/// payload cannot put a raw value back in a field that is supposed to hold one of these.
///
/// A server reproduces `init(hashing:)` as `hashlib.sha256(value.encode()).hexdigest()`: both hash
/// the string's UTF-8 bytes exactly as received, with no Unicode normalization.
public struct RemoteMediaDigest: Hashable, Sendable, Codable {
    /// 64 lowercase hexadecimal characters.
    public let hexString: String

    /// The digest of `value`'s UTF-8 bytes.
    init(hashing value: String) {
        self.hexString = SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
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
