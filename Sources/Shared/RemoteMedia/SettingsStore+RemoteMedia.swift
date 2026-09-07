import Foundation

public extension SettingsStore {
    var remoteMediaSelection: RemoteMediaSelection? {
        get {
            guard let data = prefs.data(forKey: "remoteMediaSelection") else { return nil }
            return try? JSONDecoder().decode(RemoteMediaSelection.self, from: data)
        }
        set {
            prefs.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "remoteMediaSelection")
        }
    }

    /// Identifies the current Follow lifetime, so a push token registered for it can be told apart
    /// from one registered for the last.
    ///
    /// Stopping and re-following the same player produces the same session identifier, because that
    /// is derived from the server and entity. Without this the server could not tell a token that
    /// is still current from one belonging to a relationship the user has already ended.
    var remoteMediaSessionGeneration: String? {
        get { prefs.string(forKey: "remoteMediaSessionGeneration") }
        set { prefs.set(newValue, forKey: "remoteMediaSessionGeneration") }
    }

    /// Begins a lifetime for `selection`, or ends the current one when nothing is followed.
    @discardableResult
    func startRemoteMediaSessionGeneration(following selection: RemoteMediaSelection?) -> String? {
        let generation = selection == nil ? nil : UUID().uuidString
        remoteMediaSessionGeneration = generation
        return generation
    }
}
