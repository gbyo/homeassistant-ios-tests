import Foundation

public extension SettingsStore {
    private var remoteMediaFollowRecord: RemoteMediaFollowRecord? {
        get {
            guard let data = prefs.data(forKey: "remoteMediaFollowRecord") else { return nil }
            return try? JSONDecoder().decode(RemoteMediaFollowRecord.self, from: data)
        }
        set {
            prefs.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "remoteMediaFollowRecord")
        }
    }

    var remoteMediaSelection: RemoteMediaSelection? {
        get {
            if let record = remoteMediaFollowRecord { return record.selection }
            guard let data = prefs.data(forKey: "remoteMediaSelection") else { return nil }
            return try? JSONDecoder().decode(RemoteMediaSelection.self, from: data)
        }
        set {
            if let newValue, let record = remoteMediaFollowRecord {
                remoteMediaFollowRecord = .init(selection: newValue, lifetime: record.lifetime)
            } else {
                if newValue == nil { remoteMediaFollowRecord = nil }
                prefs.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "remoteMediaSelection")
            }
        }
    }

    /// The current Follow relationship: which one it is, and where it sits in the order they were
    /// created.
    ///
    /// Stopping and re-following the same player produces the same session identifier, because that
    /// is derived from the server and entity. Without this the server could not tell a token that
    /// is still current from one belonging to a relationship the user has already ended, nor which
    /// of two registrations that reached it out of order is the newer.
    var remoteMediaFollowLifetime: RemoteMediaFollowLifetime? {
        get {
            if let record = remoteMediaFollowRecord { return record.lifetime }
            guard let data = prefs.data(forKey: "remoteMediaFollowLifetime") else { return nil }
            return try? JSONDecoder().decode(RemoteMediaFollowLifetime.self, from: data)
        }
        set {
            if let newValue, let selection = remoteMediaSelection {
                remoteMediaFollowRecord = .init(selection: selection, lifetime: newValue)
            } else if newValue == nil {
                remoteMediaFollowRecord = nil
            }
            prefs.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "remoteMediaFollowLifetime")
        }
    }

    /// How many Follow relationships this install has created.
    ///
    /// Durable and monotonic, and deliberately not a clock: a wall-clock value goes backwards when
    /// the user changes the time or a time zone crosses a boundary, and two relationships created
    /// in the same second would be indistinguishable. It does not have to mean anything beyond this
    /// install — re-registering with Home Assistant establishes a new ownership context on the
    /// server, so a counter that restarts there is not a problem.
    var remoteMediaFollowSequence: Int {
        get { max(0, prefs.integer(forKey: "remoteMediaFollowSequence")) }
        set { prefs.set(newValue, forKey: "remoteMediaFollowSequence") }
    }

    /// Begins a relationship for `selection`, or ends the current one when nothing is followed.
    ///
    /// The counter moves exactly once per relationship, and only here. Everything that happens
    /// within one — a token rotation, an extension relaunch, the host app republishing state —
    /// reuses the value this returned.
    @discardableResult
    func startRemoteMediaFollowLifetime(
        following selection: RemoteMediaSelection?
    ) -> RemoteMediaFollowLifetime? {
        guard let selection else {
            remoteMediaFollowRecord = nil
            prefs.removeObject(forKey: "remoteMediaSelection")
            prefs.removeObject(forKey: "remoteMediaFollowLifetime")
            return nil
        }
        let sequence = RemoteMediaFollowLifetime.nextSequence(after: remoteMediaFollowSequence)
        remoteMediaFollowSequence = sequence
        let lifetime = RemoteMediaFollowLifetime(generation: UUID().uuidString, sequence: sequence)
        remoteMediaFollowRecord = .init(selection: selection, lifetime: lifetime)
        prefs.removeObject(forKey: "remoteMediaSelection")
        prefs.removeObject(forKey: "remoteMediaFollowLifetime")
        return lifetime
    }

    /// Adopts a server-authoritative rename without creating a new Follow relationship.
    @discardableResult
    func adoptRemoteMediaSelectionUpdate() -> Bool {
        guard let update = RemoteMediaAuthoritativeSelectionStore.load(),
              let record = remoteMediaFollowRecord,
              record.lifetime == update.lifetime,
              record.selection.id == update.sessionId else { return false }
        defer { RemoteMediaAuthoritativeSelectionStore.clear() }
        guard record.selection != update.selection else { return false }
        remoteMediaFollowRecord = .init(selection: update.selection, lifetime: record.lifetime)
        return true
    }

    /// Gives an unordered relationship from an earlier build a place in the order.
    ///
    /// Only reachable on a development install: nothing that shipped ever wrote the old key. The
    /// alternative is a followed player whose token can never be registered until the user notices
    /// and re-follows, and adopting it costs one counter step.
    ///
    /// Returns the lifetime that is current afterwards, migrated or not.
    @discardableResult
    func migrateRemoteMediaFollowLifetime() -> RemoteMediaFollowLifetime? {
        let legacyKey = "remoteMediaSessionGeneration"
        defer { prefs.removeObject(forKey: legacyKey) }
        if let record = remoteMediaFollowRecord { return record.lifetime }
        if let selection = remoteMediaSelection, let lifetime = remoteMediaFollowLifetime {
            remoteMediaFollowRecord = .init(selection: selection, lifetime: lifetime)
            prefs.removeObject(forKey: "remoteMediaSelection")
            prefs.removeObject(forKey: "remoteMediaFollowLifetime")
            return lifetime
        }
        guard let selection = remoteMediaSelection, let generation = prefs.string(forKey: legacyKey) else {
            return remoteMediaFollowLifetime
        }
        let sequence = RemoteMediaFollowLifetime.nextSequence(after: remoteMediaFollowSequence)
        remoteMediaFollowSequence = sequence
        let lifetime = RemoteMediaFollowLifetime(generation: generation, sequence: sequence)
        remoteMediaFollowRecord = .init(selection: selection, lifetime: lifetime)
        prefs.removeObject(forKey: "remoteMediaSelection")
        prefs.removeObject(forKey: "remoteMediaFollowLifetime")
        return lifetime
    }

    /// Follow relationships that have ended locally but that Home Assistant may not know about.
    ///
    /// Identity only — no token, no secret, no URL — so this is safe in ordinary preferences. See
    /// `RemoteMediaPendingDismissal` and `RemoteMediaDismissalReconciler`.
    var remoteMediaPendingDismissals: [RemoteMediaPendingDismissal] {
        get {
            guard let data = prefs.data(forKey: "remoteMediaPendingDismissals") else { return [] }
            return (try? JSONDecoder().decode([RemoteMediaPendingDismissal].self, from: data)) ?? []
        }
        set {
            // Bounded: a server that is never reachable again must not be able to grow this
            // without limit, and the oldest unsent dismissals are the least worth keeping — the
            // sessions they name have long since had their tokens rejected by APNs.
            let bounded = newValue.suffix(Self.remoteMediaPendingDismissalLimit)
            prefs.set(
                bounded.isEmpty ? nil : try? JSONEncoder().encode(Array(bounded)),
                forKey: "remoteMediaPendingDismissals"
            )
        }
    }

    static let remoteMediaPendingDismissalLimit = 16

    /// Records that `pending` is owed to the server, replacing any earlier record of it.
    func addRemoteMediaPendingDismissal(_ pending: RemoteMediaPendingDismissal) {
        var records = remoteMediaPendingDismissals.filter { !$0.describesSameLifetime(as: pending) }
        records.append(pending)
        remoteMediaPendingDismissals = records
    }

    /// Forgets a dismissal the server has accepted.
    func removeRemoteMediaPendingDismissal(_ pending: RemoteMediaPendingDismissal) {
        remoteMediaPendingDismissals = remoteMediaPendingDismissals
            .filter { !$0.describesSameLifetime(as: pending) }
    }
}
