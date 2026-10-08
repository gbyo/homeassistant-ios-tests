import CryptoKit
import Foundation

/// A SHA-256 digest in lowercase hexadecimal: the only form an identifier takes in a snapshot.
///
/// Integrations put whatever they like in values such as `media_content_id`, including stream URLs
/// with signed query strings. Remote Now Playing needs to know whether two reports name the same
/// thing, never what the thing is, and a snapshot is published outside the app, so it carries a
/// digest and the original stays on the server.
///
/// A server reproduces `init(hashing:)` as `hashlib.sha256(value.encode()).hexdigest()`: both hash the
/// string's UTF-8 bytes exactly as received, with no Unicode normalization.
public struct RemoteMediaDigest: Hashable, Sendable {
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
}
