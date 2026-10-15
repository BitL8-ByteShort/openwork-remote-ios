import Foundation

public struct ConnectionID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
  public init() { rawValue = UUID() }
}
public enum ConnectionBackend: String, Codable, Sendable { case openCodeV2 }

/// Only a Keychain account reference belongs in persisted connection metadata.
public struct OpenCodeConnection: Codable, Sendable, Equatable {
  public let schemaVersion: Int
  public let backend: ConnectionBackend
  public let id: ConnectionID
  public let origin: URL
  public let displayName: String
  public var credentialReference: String { "opencode-v2." + id.rawValue.uuidString.lowercased() }

  public init(id: ConnectionID = ConnectionID(), origin: URL, displayName: String) throws {
    let canonical = try OpenCodeOrigin.canonical(origin)
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.utf8.count <= 256,
      !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RemoteError.invalidPairing }
    schemaVersion = 1; backend = .openCodeV2
    self.id = id; self.origin = canonical; self.displayName = name
  }
  private enum CodingKeys: String, CodingKey { case schemaVersion, backend, id, origin, displayName }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    guard try c.decode(Int.self, forKey: .schemaVersion) == 1,
      try c.decode(ConnectionBackend.self, forKey: .backend) == .openCodeV2 else {
      throw RemoteError.incompatible
    }
    try self.init(id: c.decode(ConnectionID.self, forKey: .id),
      origin: c.decode(URL.self, forKey: .origin), displayName: c.decode(String.self, forKey: .displayName))
  }
}

public struct OpenCodeTarget: Codable, Hashable, Sendable {
  public let connectionID: ConnectionID
  public let projectID: String
  public let sessionID: String
  public let directory: String
  public init(connectionID: ConnectionID, projectID: String, sessionID: String, directory: String) {
    self.connectionID = connectionID; self.projectID = projectID
    self.sessionID = sessionID; self.directory = directory
  }
}
public struct OpenCodeServerInfo: Decodable, Sendable {
  public struct Paths: Decodable, Sendable { public let tmp: String }
  public let version: String
  public let urls: [String]
  public let paths: Paths
}
