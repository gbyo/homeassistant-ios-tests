import Foundation

/// The id of a `media_player` entity, valid by construction.
///
/// Ids arrive from outside the app and end up where a stray character changes meaning, such as a
/// template the server renders, where a quote would end the literal. Holding one of these proves the
/// check already happened.
///
/// Accepted: `media_player.` followed by lowercase ASCII letters, digits and underscores, not starting
/// or ending with an underscore, with no two underscores in a row, at most 255 characters. That is
/// Core's `valid_entity_id` (`homeassistant/core.py`) and `MAX_LENGTH_STATE_ENTITY_ID`. Its `(?!.+__)`
/// lookahead is anchored at the start of the whole id, so doubled underscores are rejected in the
/// object id too; Core's `test_valid_entity_id` lists `light.kitchen__ceiling` as invalid.
///
/// It is stricter than Core in two ways no slugified id is affected by: Core's `\d` also matches
/// non-ASCII digits, and its `$` also matches before a trailing newline.
public struct RemoteMediaEntityId: Hashable, Sendable {
    public let rawValue: String

    /// `nil` unless `rawValue` is a well-formed `media_player` entity id.
    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    private static let domainPrefix = Array("media_player.".utf8)
    private static let maximumLength = 255

    private static func isValid(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count <= maximumLength, bytes.starts(with: domainPrefix) else { return false }
        let objectId = bytes.dropFirst(domainPrefix.count)
        guard let first = objectId.first, let last = objectId.last,
              first != UInt8(ascii: "_"), last != UInt8(ascii: "_") else { return false }
        var previous: UInt8 = 0
        for byte in objectId {
            switch byte {
            case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "0") ... UInt8(ascii: "9"):
                break
            case UInt8(ascii: "_") where previous != UInt8(ascii: "_"):
                break
            default:
                return false
            }
            previous = byte
        }
        return true
    }
}
