import Foundation

/// What is known about the cover of the track a snapshot shows: that no report offered one, that one
/// exists but is not prepared yet, or where the prepared copy is. Only `available` carries a
/// descriptor, so a descriptor and a status can never disagree.
///
/// On the wire this is an object with a `state` of `absent`, `deferred` or `available`, and for
/// `available` exactly one of `cacheKey` or `url`. Anything else fails to decode.
public enum RemoteMediaArtwork: Equatable, Sendable, Codable {
    /// No picture was offered. This describes a report, not the track: Home Assistant leaves
    /// `entity_picture` out both when an entity has no picture and while an integration refreshes its
    /// attributes, and a report cannot say which. So `absent` is never a removal. A report that omits
    /// the picture keeps the one already known for the same track (`RemoteMediaSnapshotReducer`), and
    /// a cover ends with its track.
    case absent
    /// A cover exists but has not been prepared yet. `RemoteMediaEntityState.artworkSource` says
    /// where to get it.
    case deferred
    /// The cover has been prepared and stored, or can be fetched by anyone. Never read from Home
    /// Assistant: on this device it exists only in what
    /// `RemoteMediaEntityState.displayedSnapshot(preparedArtworkFrom:)` returns, and otherwise it is
    /// decoded from a payload.
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
