import ExtensionFoundation
import NowPlaying
import Shared

@main
struct HomeAssistantRemoteMediaExtension: RemoteMediaSessionExtension {
    var configuration: RemoteMediaSessionExtensionConfiguration<Self> {
        .init(extension: self)
    }

    func session(_ attributes: Shared.RemoteMediaSessionAttributes) async throws -> HomeAssistantRemoteMediaSession {
        Current.Log.info("Remote media extension creating session")
        return HomeAssistantRemoteMediaSession(attributes: attributes)
    }
}
