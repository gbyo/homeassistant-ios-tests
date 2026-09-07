import ExtensionFoundation
import NowPlaying

@main
struct HomeAssistantRemoteMediaExtension: RemoteMediaSessionExtension {
    var configuration: RemoteMediaSessionExtensionConfiguration<Self> {
        .init(extension: self)
    }

    func session(_ attributes: RemoteMediaSessionAttributes) async throws -> HomeAssistantRemoteMediaSession {
        RemoteMediaLog.logger.info("Creating session")
        RemoteMediaFootprint.log("extension entry")
        return HomeAssistantRemoteMediaSession(attributes: attributes)
    }
}
