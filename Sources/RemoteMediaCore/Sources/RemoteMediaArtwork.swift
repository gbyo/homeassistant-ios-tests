import Foundation

/// What a report says about its track's artwork, stated outright: that it offers none, that a cover
/// exists but is not prepared yet, or where the prepared cover is. A single optional could not tell
/// the first two apart, and a descriptor beside a separate status could contradict it; here only
/// `available` carries a descriptor. How reports combine is `RemoteMediaSnapshotReducer`'s business.
///
/// On the wire this is an object with a `state` of `absent`, `deferred` or `available`, and for
/// `available` exactly one of `cacheKey` or `url`. Anything else fails to decode.
public enum RemoteMediaArtwork: Equatable, Sendable, Codable {
    case absent
    /// A cover exists but has not been prepared yet.
    case deferred
    case available(RemoteMediaArtworkDescriptor)

    private enum CodingKeys: String, CodingKey {
        case state, cacheKey, url
    }

    private enum State: String, Codable {
        case absent, deferred, available
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cacheKey = try container.decodeIfPresent(RemoteMediaDigest.self, forKey: .cacheKey)
        let url = try container.decodeIfPresent(RemoteMediaArtworkURL.self, forKey: .url)
        switch try container.decode(State.self, forKey: .state) {
        case .absent where cacheKey == nil && url == nil:
            self = .absent
        case .deferred where cacheKey == nil && url == nil:
            self = .deferred
        case .available:
            switch (cacheKey, url) {
            case let (cacheKey?, nil): self = .available(.cached(cacheKey))
            case let (nil, url?): self = .available(.remote(url))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .state,
                    in: container,
                    debugDescription: "Available artwork needs exactly one of cacheKey or url"
                )
            }
        case .absent, .deferred:
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Only available artwork carries a cacheKey or url"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent:
            try container.encode(State.absent, forKey: .state)
        case .deferred:
            try container.encode(State.deferred, forKey: .state)
        case let .available(.cached(cacheKey)):
            try container.encode(State.available, forKey: .state)
            try container.encode(cacheKey, forKey: .cacheKey)
        case let .available(.remote(url)):
            try container.encode(State.available, forKey: .state)
            try container.encode(url, forKey: .url)
        }
    }
}
