import Foundation

public enum MutationAction: String, Codable, Sendable { case create, stop, approval }
public struct MutationKey: Codable, Sendable, Hashable {
  public let hostId: String
  public let workspaceId: String
  public let sessionId: String?
  public let action: MutationAction
  public let approvalId: String?
  public let revision: String?
  public init(hostId: String, workspaceId: String, sessionId: String?, action: MutationAction, approvalId: String? = nil, revision: String? = nil) {
    self.hostId = hostId
    self.workspaceId = workspaceId
    self.sessionId = sessionId
    self.action = action
    self.approvalId = approvalId
    self.revision = revision
  }
}
public struct MutationState: Codable, Sendable {
  private var requests: [MutationKey: UUID] = [:]
  private var uncertain: Set<MutationKey> = []
  public init() {}
  public func requestId(for key: MutationKey) -> UUID? { requests[key] }
  public func requiresReview(_ key: MutationKey) -> Bool { requests[key] != nil }
  public mutating func begin(_ key: MutationKey) throws -> UUID {
    guard requests[key] == nil else { throw RemoteError.unavailable }
    let id = UUID()
    requests[key] = id
    return id
  }
  public mutating func finish(_ key: MutationKey, accepted: Bool) {
    if accepted {
      requests.removeValue(forKey: key)
      uncertain.remove(key)
    } else {
      uncertain.insert(key)
    }
  }
  public mutating func recoverPending() { uncertain.formUnion(requests.keys) }
  public mutating func reviewed(_ key: MutationKey) {
    guard uncertain.contains(key) else { return }
    requests.removeValue(forKey: key)
    uncertain.remove(key)
  }
}
/// Retains loaded earlier pages when the first page changes after a stream hint.
public struct PagedSnapshot<Row: Identifiable & Sendable>: Sendable where Row.ID == String {
  public private(set) var rows: [Row] = []
  public private(set) var cursor: String?
  private var initialized = false
  public init() {}
  public mutating func latest(_ rows: [Row], cursor: String?) {
    let ids = Set(rows.map(\.id))
    self.rows = rows + self.rows.filter { !ids.contains($0.id) }
    if !initialized {
      self.cursor = cursor
      initialized = true
    }
  }
  public mutating func remove(id: String) { rows.removeAll { $0.id == id } }
  public mutating func older(_ rows: [Row], cursor: String?) {
    let ids = Set(self.rows.map(\.id))
    self.rows += rows.filter { !ids.contains($0.id) }
    self.cursor = cursor
    initialized = true
  }
}
