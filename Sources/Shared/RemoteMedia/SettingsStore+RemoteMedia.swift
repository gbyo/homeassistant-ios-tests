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
}
