#if os(iOS) && !targetEnvironment(macCatalyst)
import NowPlaying

@available(iOS 27.0, *)
public struct RemoteMediaSessionAttributes: NowPlaying.RemoteMediaSessionAttributes {
    public let snapshot: RemoteMediaSnapshot
    public var id: String { snapshot.id }

    public init(snapshot: RemoteMediaSnapshot) { self.snapshot = snapshot }
}
#endif
