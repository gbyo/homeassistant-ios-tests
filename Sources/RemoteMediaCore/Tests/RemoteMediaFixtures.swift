import Foundation
import RemoteMediaCore
import Testing

/// Inputs written the way they actually arrive: Home Assistant attributes as the JSON a server sends,
/// parsed by `JSONSerialization` like every real caller's are, and wire payloads as literal JSON.
enum RemoteMediaFixtures {
    static var entityId: RemoteMediaEntityId {
        get throws { try #require(RemoteMediaEntityId("media_player.living_room")) }
    }

    static func attributes(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }

    static func mapped(_ state: String = "playing", _ json: String = "{}") throws -> RemoteMediaEntityState {
        let entityId = try entityId
        let attributes = try attributes(json)
        return RemoteMediaSnapshotMapper.map(
            serverId: "server-1",
            entityId: entityId,
            state: state,
            attributes: attributes
        )
    }

    static func report(_ state: String = "playing", _ json: String = "{}") throws -> RemoteMediaSnapshot {
        try mapped(state, json).snapshot
    }

    static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// `value` encoded and read back as a plain JSON object, for comparing against a literal.
    static func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        return try #require(object as? [String: Any])
    }

    /// Structural JSON equality, so `180` and `180.0` compare equal the way a decoder treats them.
    static func isEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }
}
