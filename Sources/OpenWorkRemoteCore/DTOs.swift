import Foundation

public struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
  public let data: Value
  public let cursor: String?
}
public struct Capabilities: Codable, Sendable {
  public let renameSession: Bool?
  public let modelSettings: Bool?
  public let savedPermissions: Bool?
  public let questions: Bool?
  public let attachments: Bool?
  public let artifacts: Bool?
  public let changes: Bool?
  public let sessionGroups: Bool?
  public let forkSession: Bool?
  public let deleteSession: Bool?
  public let searchSessions: Bool?
  public let workspaceDefaults: Bool?
  public let skillsRead: Bool?
  public let skillsWrite: Bool?
  public let skillsSelect: Bool?
  public let automationsRead: Bool?
  public let automationsWrite: Bool?
  public let readSessions: Bool
  public let readMessages: Bool
  public let readStatus: Bool
  public let events: Bool
  public let createSession: Bool
  public let sendText: Bool
  public let stop: Bool
  public let readApprovals: Bool
  public let replyApproval: Bool
  public let maxPromptBytes: Int
  public let protocolVersion: Int
}
public struct Host: Codable, Sendable {
  public let hostId: String
  public let displayName: String
  public let platform: String
  public let architecture: String
  public let runtimeKind: String
  public let protocolVersion: Int
  public let upstreamVersion: String
  public let compatibility: String
  public let capabilities: Capabilities
}
public struct Workspace: Codable, Sendable, Identifiable, Hashable {
  public let id: String
  public let name: String
}
public struct ChatSession: Codable, Sendable, Identifiable, Hashable {
  public let id: String
  public let workspaceId: String
  public let title: String
  public let updatedAt: String
  public let modelLabel: String?
  public let status: String
}
public struct MessageBlock: Codable, Sendable, Equatable {
  public let kind: String
  public let text: String?
  public let language: String?
  public let name: String?
  public let status: String?
  public let summary: String?
  public let label: String?
  enum CodingKeys: String, CodingKey { case kind, text, language, name, status, summary, label }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let k = try c.decode(String.self, forKey: .kind)
    guard ["text", "code", "tool", "omitted", "unsupported"].contains(k) else {
      kind = "unsupported"
      text = nil
      language = nil
      name = nil
      status = nil
      summary = nil
      label = "Content available on computer"
      return
    }
    kind = k
    text = try c.decodeIfPresent(String.self, forKey: .text)
    language = try c.decodeIfPresent(String.self, forKey: .language)
    name = try c.decodeIfPresent(String.self, forKey: .name)
    status = try c.decodeIfPresent(String.self, forKey: .status)
    summary = try c.decodeIfPresent(String.self, forKey: .summary)
    label = try c.decodeIfPresent(String.self, forKey: .label)
  }
}
public struct ChatMessage: Codable, Sendable, Identifiable, Equatable {
  public let id: String
  public let sessionId: String
  public let role: String
  public let createdAt: String
  public let blocks: [MessageBlock]
  public let state: String
}
public struct SessionStatus: Codable, Sendable {
  public let phase: String
  public let observedAt: String
  public let activeTurnId: String?
  public let errorCode: String?
}
public struct Approval: Codable, Sendable, Identifiable {
  public let id: String
  public let sessionId: String
  public let kind: String
  public let title: String
  public let details: String
  public let revision: String
  public let supportedDecisions: [String]
  public let createdAt: String
}
public struct MutationReceipt: Codable, Sendable {
  public let requestId: String
  public let resourceId: String?
  public let resourceRevision:String?
  public let state: String
  public let observedAt: String
}
public struct PairingPayload: Codable, Sendable {
  public let protocolVersion: Int
  public let origin: String
  public let pairingId: String
  public let secret: String
  public static func decode(_ text: String) throws -> PairingPayload {
    guard text.utf8.count <= 4096, let data = text.data(using: .utf8) else {
      throw RemoteError.invalidPairing
    }
    let p = try JSONDecoder().decode(Self.self, from: data)
    _ = try PairingValidation.origin(p.origin)
    guard p.protocolVersion == 1, UUID(uuidString: p.pairingId) != nil,
      p.secret.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
    else { throw RemoteError.invalidPairing }
    return p
  }
}
public struct PairClaim: Decodable, Sendable {
  public let claimId: String
  public let pollToken: String
  public let expiresAt: String
}
public struct PairPoll: Decodable, Sendable {
  public let state: String
  public let credential: String?
  public let host: Host?
  public let allowedWorkspaces: [String]?
}
public struct EventHint: Decodable, Sendable {
  public let kind: String
  public let workspaceId: String?
  public let sessionId: String?
}
