import ExtensionFoundation
import NowPlaying

@main
struct HomeAssistantRemoteMediaExtension: RemoteMediaSessionExtension {
    var configuration: RemoteMediaSessionExtensionConfiguration<Self> {
        .init(extension: self)
    }

    func session(_ attributes: RemoteMediaSessionAttributes) async throws -> HomeAssistantRemoteMediaSession {
        RemoteMediaLog.logger.info("Creating session")
        #if DEBUG
            RemoteMediaFootprint.log("extension entry")
        #endif
        return HomeAssistantRemoteMediaSession(attributes: attributes)
    }
}
