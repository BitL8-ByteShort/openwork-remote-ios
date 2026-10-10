import Foundation

private struct ActionKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func actionID(_ value: String) throws -> String {
  guard value.utf8.count <= 200,
    value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
  else { throw RemoteError.invalidResponse }
  return value
}
public struct SessionActionPreview: Decodable, Sendable, Equatable {
  public let revision: String, title: String
  public let running: Bool, forkAvailable: Bool, deleteAvailable: Bool
  public let deleteReason: String?
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case revision, title, running, forkAvailable, deleteAvailable, deleteReason
  }
  public init(from decoder: any Decoder) throws {
    let keys = try decoder.container(keyedBy: ActionKey.self)
    guard Set(keys.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
      throw RemoteError.invalidResponse
    }
    let c = try decoder.container(keyedBy: CodingKeys.self)
    revision = try c.decode(String.self, forKey: .revision)
    title = try c.decode(String.self, forKey: .title)
    running = try c.decode(Bool.self, forKey: .running)
    forkAvailable = try c.decode(Bool.self, forKey: .forkAvailable)
    deleteAvailable = try c.decode(Bool.self, forKey: .deleteAvailable)
    deleteReason = try c.decodeIfPresent(String.self, forKey: .deleteReason)
    guard revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      title.utf16.count <= 4096, forkAvailable == !running,
      deleteAvailable == (deleteReason == nil),
      deleteReason == nil || ["running", "linkedChats"].contains(deleteReason!),
      running == (deleteReason == "running")
    else { throw RemoteError.invalidResponse }
  }
}
public enum SessionAction: Codable, Sendable, Equatable {
  case fork(beforeMessageId: String?)
  case delete
}
extension BridgeClient {
  public func sessionActions(_ wid: String, _ sid: String) async throws -> SessionActionPreview {
    try await decode(
      Envelope<SessionActionPreview>.self,
      path: "/v1/workspaces/" + (try actionID(wid)) + "/sessions/" + (try actionID(sid))
        + "/actions"
    ).data
  }
  public func sessionAction(
    _ wid: String, _ sid: String, action: SessionAction, revision: String, requestId: UUID
  ) async throws -> MutationReceipt {
    guard revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
      throw RemoteError.invalidResponse
    }
    var path = "/v1/workspaces/" + (try actionID(wid)) + "/sessions/" + (try actionID(sid))
    struct Body: Encodable {
      let requestId: String, revision: String
      var beforeMessageId: String?
      var fork: Bool
      private enum CodingKeys: String, CodingKey { case requestId, revision, beforeMessageId }
      func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(revision, forKey: .revision)
        if fork { try c.encode(beforeMessageId, forKey: .beforeMessageId) }
      }
    }
    let isFork: Bool
    var before: String?
    switch action {
    case .fork(let message):
      isFork = true
      before = message
      if let message { _ = try actionID(message) }
      path += "/fork"
    case .delete:
      isFork = false
      path += "/delete"
    }
    let body = Body(
      requestId: requestId.uuidString.lowercased(), revision: revision, beforeMessageId: before,
      fork: isFork)
    let r = try await decode(
      Envelope<MutationReceipt>.self, path: path, method: "POST", body: JSONEncoder().encode(body)
    ).data
    guard r.requestId == body.requestId,
      ["pending", "accepted", "confirmed", "rejected", "outcome_unknown"].contains(r.state)
    else { throw RemoteError.invalidResponse }
    if let resource = r.resourceId {
      _ = try actionID(resource)
      guard isFork ? resource != sid : resource == sid else { throw RemoteError.invalidResponse }
    }
    if ["accepted", "confirmed"].contains(r.state) {
      guard r.resourceId != nil else { throw RemoteError.invalidResponse }
    }
    return r
  }
}
