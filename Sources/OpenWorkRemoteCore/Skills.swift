import Foundation

private struct SkillKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func skillClosed(_ decoder: any Decoder, _ keys: [String]) throws {
  let c = try decoder.container(keyedBy: SkillKey.self)
  guard Set(c.allKeys.map(\.stringValue)) == Set(keys) else { throw RemoteError.invalidResponse }
}
public enum SkillValidation {
  public static func id(_ value: String) throws {
    guard value.range(of: "^skill_[a-f0-9]{64}$", options: .regularExpression) != nil else {
      throw RemoteError.invalidResponse
    }
  }
  public static func revision(_ value: String) throws {
    guard value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
      throw RemoteError.invalidResponse
    }
  }
  public static func selection(_ ids: [String]) throws {
    guard ids.count <= 8, Set(ids).count == ids.count else { throw RemoteError.invalidResponse }
    for id in ids { try self.id(id) }
  }
  public static func name(_ value: String) throws {
    guard value.count <= 64,
      value.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil
    else { throw RemoteError.invalidResponse }
  }
}
public struct SkillSummary: Codable, Sendable, Equatable, Identifiable {
  public enum Source: String, Codable, Sendable { case workspace, inherited, global, managed }
  public let id: String, name: String, description: String, source: Source, editable: Bool,
    selectable: Bool, revision: String
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, name, description, source, editable, selectable, revision
  }
  public init(from decoder: any Decoder) throws {
    try skillClosed(decoder, CodingKeys.allCases.map(\.rawValue))
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    description = try c.decode(String.self, forKey: .description)
    source = try c.decode(Source.self, forKey: .source)
    editable = try c.decode(Bool.self, forKey: .editable)
    selectable = try c.decode(Bool.self, forKey: .selectable)
    revision = try c.decode(String.self, forKey: .revision)
    try SkillValidation.id(id)
    try SkillValidation.revision(revision)
    guard !name.isEmpty, name.unicodeScalars.count <= 200, description.unicodeScalars.count <= 1024,
      !editable || source == .workspace
    else { throw RemoteError.invalidResponse }
  }
  public var sourceLabel: String {
    switch source {
    case .workspace: return "Workspace skill"
    case .inherited: return "Inherited skill"
    case .global: return "Global skill"
    case .managed: return "Managed skill"
    }
  }
}
public struct SkillCatalog: Decodable, Sendable {
  public let items: [SkillSummary], revision: String
  private enum CodingKeys: String, CodingKey, CaseIterable { case items, revision }
  public init(from decoder: any Decoder) throws {
    try skillClosed(decoder, CodingKeys.allCases.map(\.rawValue))
    let c = try decoder.container(keyedBy: CodingKeys.self)
    items = try c.decode([SkillSummary].self, forKey: .items)
    revision = try c.decode(String.self, forKey: .revision)
    try SkillValidation.revision(revision)
    guard items.count <= 2000, Set(items.map(\.id)).count == items.count else {
      throw RemoteError.invalidResponse
    }
  }
}
public struct SkillDetail: Decodable, Sendable {
  public let item: SkillSummary, content: String?
  private enum CodingKeys: String, CodingKey, CaseIterable { case item, content }
  public init(from decoder: any Decoder) throws {
    try skillClosed(decoder, CodingKeys.allCases.map(\.rawValue))
    let c = try decoder.container(keyedBy: CodingKeys.self)
    item = try c.decode(SkillSummary.self, forKey: .item)
    content = try c.decodeIfPresent(String.self, forKey: .content)
    guard (content?.utf8.count ?? 0) <= 65536 else { throw RemoteError.oversized }
  }
}
public enum SkillAction: Codable, Sendable, Equatable {
  case save(name: String, content: String, revision: String?, catalogRevision: String)
  case delete(id: String, revision: String)
  public func validate() throws {
    switch self {
    case .save(let name, let content, let revision, let catalogRevision):
      try SkillValidation.name(name)
      try SkillValidation.revision(catalogRevision)
      if let revision { try SkillValidation.revision(revision) }
      guard !content.isEmpty else { throw RemoteError.invalidResponse }
      guard content.utf8.count <= 65536 else { throw RemoteError.oversized }
    case .delete(let id, let revision):
      try SkillValidation.id(id)
      try SkillValidation.revision(revision)
    }
  }
  public func requestBody(requestId: UUID) throws -> Data {
    try validate()
    let body: Data
    switch self {
    case .save(let name, let content, let revision, let catalogRevision):
      struct Body: Encodable {
        let requestId: String, name: String, content: String, revision: String?,
          catalogRevision: String
        private enum CodingKeys: String, CodingKey {
          case requestId, name, content, revision, catalogRevision
        }
        func encode(to encoder: any Encoder) throws {
          var c = encoder.container(keyedBy: CodingKeys.self)
          try c.encode(requestId, forKey: .requestId)
          try c.encode(name, forKey: .name)
          try c.encode(content, forKey: .content)
          try c.encode(revision, forKey: .revision)
          try c.encode(catalogRevision, forKey: .catalogRevision)
        }
      }
      body = try JSONEncoder().encode(
        Body(
          requestId: requestId.uuidString.lowercased(), name: name, content: content,
          revision: revision, catalogRevision: catalogRevision))
    case .delete(let id, let revision):
      body = try JSONEncoder().encode([
        "requestId": requestId.uuidString.lowercased(), "id": id, "revision": revision,
      ])
    }
    guard body.count <= 40 * 1024 else { throw RemoteError.oversized }
    return body
  }
}
extension BridgeClient {
  private func skillsPath(_ wid: String) throws -> String {
    guard wid.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil else {
      throw RemoteError.invalidResponse
    }
    return "/v1/workspaces/" + wid + "/skills"
  }
  public func skills(_ wid: String) async throws -> SkillCatalog {
    try await decode(Envelope<SkillCatalog>.self, path: try skillsPath(wid)).data
  }
  public func skill(_ wid: String, id: String) async throws -> SkillDetail {
    try SkillValidation.id(id)
    return try await decode(Envelope<SkillDetail>.self, path: try skillsPath(wid) + "/" + id).data
  }
  public func changeSkill(_ wid: String, action: SkillAction, requestId: UUID) async throws
    -> MutationReceipt
  {
    try Task.checkCancellation()
    let body = try action.requestBody(requestId: requestId)
    let path: String
    switch action {
    case .save: path = try skillsPath(wid) + "/save"
    case .delete: path = try skillsPath(wid) + "/delete"
    }
    let receipt = try await decode(
      Envelope<MutationReceipt>.self, path: path, method: "POST", body: body
    ).data
    guard receipt.requestId == requestId.uuidString.lowercased(),
      ["accepted", "confirmed", "rejected", "pending", "outcome_unknown"].contains(receipt.state)
    else { throw RemoteError.invalidResponse }
    if case .save = action, ["accepted", "confirmed"].contains(receipt.state) {
      guard let revision = receipt.resourceRevision else { throw RemoteError.invalidResponse }
      try SkillValidation.revision(revision)
    }
    if let resource = receipt.resourceId {
      try SkillValidation.id(resource)
      if case .delete(let id, _) = action, resource != id { throw RemoteError.invalidResponse }
    } else if ["accepted", "confirmed"].contains(receipt.state) {
      throw RemoteError.invalidResponse
    }
    return receipt
  }
}
