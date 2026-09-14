import Foundation

/// Cross-process handoff for a server-authoritative entity rename.
public enum RemoteMediaAuthoritativeSelectionStore {
    private static let key = "remoteMediaAuthoritativeSelection"

    public static var defaults: UserDefaults? = RemoteMediaAppGroup.identifier
        .flatMap(UserDefaults.init(suiteName:))

    public static func load() -> RemoteMediaAuthoritativeSelection? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RemoteMediaAuthoritativeSelection.self, from: data)
    }

    public static func save(_ update: RemoteMediaAuthoritativeSelection) {
        defaults?.set(try? JSONEncoder().encode(update), forKey: key)
    }

    public static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
