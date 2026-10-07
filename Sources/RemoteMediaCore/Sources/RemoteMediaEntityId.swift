import Foundation

/// The id of a `media_player` entity, valid by construction.
///
/// Ids arrive from outside the app — a server's entity list, something persisted, a payload —
/// and end up in places where a stray character changes meaning, such as a template the server
/// renders, where a quote would end the literal the id sits in. Holding one of these, rather than a
/// `String`, is what proves the check already happened, so no consumer has to remember to repeat it.
///
/// Accepted: `media_player.` followed by lowercase ASCII letters, digits and underscores, not
/// starting or ending with an underscore, with no two underscores in a row, at most 255 characters.
///
/// That is Home Assistant Core's `valid_entity_id` (`homeassistant/core.py`), including the doubled
/// underscore rule: its `(?!.+__)` lookahead sits in the fragment named `_DOMAIN`, but it is
/// anchored at the start of the whole id, so it applies to the object id too, and Core's own
/// `test_valid_entity_id` lists `light.kitchen__ceiling` as invalid. The 255 limit is
/// `MAX_LENGTH_STATE_ENTITY_ID`, which the entity registry generates within.
///
/// Two departures are deliberately stricter than Core, and no slugified entity id is affected by
/// either: Core's `\d` also matches non-ASCII Unicode digits, and its `$` also matches before a
/// trailing newline. Both are rejected here.
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
