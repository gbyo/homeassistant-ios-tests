import ExtensionFoundation
import NowPlaying
import Shared

@main
struct HomeAssistantRemoteMediaExtension: RemoteMediaSessionExtension {
    var configuration: RemoteMediaSessionExtensionConfiguration<Self> {
        .init(extension: self)
    }

    func session(_ attributes: Shared.RemoteMediaSessionAttributes) async throws -> HomeAssistantRemoteMediaSession {
        RemoteMediaLog.logger.info("Creating session")
        return HomeAssistantRemoteMediaSession(attributes: attributes)
    }
}
