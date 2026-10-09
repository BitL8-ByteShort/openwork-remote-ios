import Foundation

private struct GroupKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func closedGroup(_ decoder: any Decoder, _ keys: [String]) throws {
  let c = try decoder.container(keyedBy: GroupKey.self)
  guard Set(c.allKeys.map(\.stringValue)).isSubset(of: Set(keys)) else {
    throw RemoteError.invalidResponse
  }
}
private func groupID(_ value: String, maximum: Int = 128) throws -> String {
  guard value.utf8.count <= maximum,
    value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
  else { throw RemoteError.invalidResponse }
  return value
}
public struct SessionGroup: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let label: String
  public static func label(_ value: String) throws -> String {
    let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !label.isEmpty, label.unicodeScalars.count <= 100, label.utf16.count <= 120,
      !label.unicodeScalars.contains(where: {
        $0.value < 32 || $0.value == 127 || (0x202a...0x202e).contains($0.value)
          || (0x2066...0x2069).contains($0.value)
      })
    else { throw RemoteError.invalidResponse }
    return label
  }
  private enum CodingKeys: String, CodingKey, CaseIterable { case id, label }
  public init(from decoder: any Decoder) throws {
    try closedGroup(decoder, CodingKeys.allCases.map(\.rawValue))
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    label = try c.decode(String.self, forKey: .label)
    _ = try groupID(id)
    guard try Self.label(label) == label else { throw RemoteError.invalidResponse }
  }
}
public struct GroupSnapshot: Decodable, Sendable, Equatable {
  public let revision: String
  public let groups: [SessionGroup]
  public let assignments: [String: String]
  private enum CodingKeys: String, CodingKey, CaseIterable { case revision, groups, assignments }
  public init(from decoder: any Decoder) throws {
    try closedGroup(decoder, CodingKeys.allCases.map(\.rawValue))
    let c = try decoder.container(keyedBy: CodingKeys.self)
    revision = try c.decode(String.self, forKey: .revision)
    groups = try c.decode([SessionGroup].self, forKey: .groups)
    assignments = try c.decode([String: String].self, forKey: .assignments)
    let ids = Set(groups.map(\.id))
    guard revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      groups.count <= 100, ids.count == groups.count, assignments.count <= 10000
    else { throw RemoteError.invalidResponse }
    for (sid, gid) in assignments {
      _ = try groupID(sid, maximum: 200)
      guard ids.contains(gid) else { throw RemoteError.invalidResponse }
    }
  }
}
public enum GroupAction: Codable, Sendable, Equatable {
  case create(label: String)
  case rename(id: String, label: String)
  case reorder(ids: [String])
  case assign(sessionId: String, groupId: String?)
  case remove(id: String)
}
extension BridgeClient {
  public func sessionGroups(_ wid: String) async throws -> GroupSnapshot {
    try await decode(
      Envelope<GroupSnapshot>.self, path: "/v1/workspaces/" + (try groupID(wid)) + "/session-groups"
    ).data
  }
  public func changeGroup(_ wid: String, action: GroupAction, revision: String, requestId: UUID)
    async throws -> MutationReceipt
  {
    guard revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
      throw RemoteError.invalidResponse
    }
    let base = "/v1/workspaces/" + (try groupID(wid)) + "/session-groups"
    struct Body: Encodable {
      let requestId: String
      let revision: String
      var label: String?
      var groupIds: [String]?
      var groupId: String?
      var assignment = false
      private enum CodingKeys: String, CodingKey {
        case requestId, revision, label, groupIds, groupId
      }
      func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(revision, forKey: .revision)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(groupIds, forKey: .groupIds)
        if assignment { try c.encode(groupId, forKey: .groupId) }
      }
    }
    var body = Body(requestId: requestId.uuidString.lowercased(), revision: revision)
    var path = base
    var expected: String?
    switch action {
    case .create(let label):
      body.label = try SessionGroup.label(label)
      expected = "grp_remote_" + body.requestId.replacingOccurrences(of: "-", with: "")
    case .rename(let id, let label):
      path += "/" + (try groupID(id)) + "/rename"
      body.label = try SessionGroup.label(label)
      expected = id
    case .remove(let id):
      path += "/" + (try groupID(id)) + "/remove"
      expected = id
    case .reorder(let ids):
      guard ids.count <= 100, Set(ids).count == ids.count else { throw RemoteError.invalidResponse }
      for id in ids { _ = try groupID(id) }
      path += "/reorder"
      body.groupIds = ids
    case .assign(let sid, let gid):
      path += "/assignments/" + (try groupID(sid, maximum: 200))
      if let gid { _ = try groupID(gid) }
      body.groupId = gid
      body.assignment = true
      expected = sid
    }
    let receipt = try await decode(
      Envelope<MutationReceipt>.self, path: path, method: "POST",
      body: try JSONEncoder().encode(body)
    ).data
    guard receipt.requestId == body.requestId,
      ["pending", "accepted", "confirmed", "rejected", "outcome_unknown"].contains(receipt.state),
      receipt.resourceId == nil || receipt.resourceId == expected,
      !["accepted", "confirmed"].contains(receipt.state) || receipt.resourceId == expected
    else { throw RemoteError.invalidResponse }
    return receipt
  }
}
