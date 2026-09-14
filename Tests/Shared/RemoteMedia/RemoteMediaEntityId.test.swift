import RemoteMediaCore
import Testing

struct RemoteMediaEntityIdTests {
    @Test(arguments: [
        "media_player.speaker",
        "media_player.living_room_2",
        "media_player._legacy__name_",
    ])
    func validMediaPlayerIDsAreAccepted(_ entityId: String) {
        #expect(RemoteMediaEntityId.isValid(entityId))
    }

    @Test(arguments: [
        "light.speaker",
        "media_player.",
        "media_player.Uppercase",
        "media_player.bad-name",
        "media_player.speaker' }} malicious {{ '",
    ])
    func invalidOrTemplateBreakingIDsAreRejected(_ entityId: String) {
        #expect(!RemoteMediaEntityId.isValid(entityId))
    }
}
