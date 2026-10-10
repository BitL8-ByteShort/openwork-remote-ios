import Foundation

public struct DraftKey: Codable, Sendable, Hashable {
  public let hostId: String
  public let workspaceId: String
  public let sessionId: String
  public init(hostId: String, workspaceId: String, sessionId: String) {
    self.hostId = hostId
    self.workspaceId = workspaceId
    self.sessionId = sessionId
  }
}
public struct SendIntent: Codable, Sendable {
  public let key: DraftKey
  public let text: String
  public let requestId: UUID
  public let attachmentIds: [String]?
  public let selectedSkillIds: [String]?
}
public struct ConversationState: Codable, Sendable {
  public private(set) var selected: DraftKey?
  public private(set) var uncertain: Set<DraftKey> = []
  private var drafts: [DraftKey: String] = [:]
  private var pending: [DraftKey: UUID] = [:]
  private var skillSelections:[DraftKey:[String]]?
  public init() {}
  public var selectedSkills:[String]{selected.flatMap{skillSelections?[$0]} ?? []}
  public mutating func setSelectedSkills(_ ids:[String])throws{try SkillValidation.selection(ids);guard let selected else{throw RemoteError.unavailable};if skillSelections==nil{skillSelections=[:]};skillSelections?[selected]=ids}
  public var currentDraft: String { selected.flatMap { drafts[$0] } ?? "" }
  public mutating func select(_ key: DraftKey) { selected = key }
  public mutating func setDraft(_ text: String) { if let selected { drafts[selected] = text } }
  public func draft(for key: DraftKey) -> String { drafts[key] ?? "" }
  public mutating func beginSend(ready: Bool, attachmentIds: [String] = [], selectedSkillIds: [String]? = nil) throws -> SendIntent {
    guard ready, let selected, pending[selected] == nil, !uncertain.contains(selected),
      !currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachmentIds.isEmpty
    else { throw RemoteError.unavailable }
    guard currentDraft.utf8.count <= 32768 else { throw RemoteError.oversized }
    if !attachmentIds.isEmpty { try AttachmentValidation.prompt(text:currentDraft,ids:attachmentIds) }
    let selectedSkillIds=selectedSkillIds ?? selectedSkills
    try SkillValidation.selection(selectedSkillIds)
    let id = UUID()
    pending[selected] = id
    return SendIntent(key: selected, text: currentDraft, requestId: id, attachmentIds:attachmentIds.isEmpty ? nil : attachmentIds,selectedSkillIds:selectedSkillIds.isEmpty ? nil:selectedSkillIds)
  }
  public mutating func applyReceipt(_ intent: SendIntent, accepted: Bool) {
    if accepted { pending.removeValue(forKey: intent.key) }
    if accepted {
      if drafts[intent.key] == intent.text { drafts[intent.key] = "" }
      if skillSelections?[intent.key]==intent.selectedSkillIds{skillSelections?.removeValue(forKey:intent.key)}
      uncertain.remove(intent.key)
    } else {
      uncertain.insert(intent.key)
    }
  }
  public mutating func rejectBeforePrompt(_ intent:SendIntent) {
    guard pending[intent.key]==intent.requestId else{return}
    pending.removeValue(forKey:intent.key);uncertain.remove(intent.key)
  }
  public mutating func recoverPending() {
    uncertain.formUnion(pending.keys)
  }
  public func pendingRequestId(for key: DraftKey) -> UUID? { pending[key] }
  public mutating func deselect() { selected = nil }
  public mutating func clearDraftText() {
    drafts.removeAll()
    skillSelections?.removeAll()
    // Request IDs and uncertain outcomes are recovery evidence, not unsent text.
  }
  public mutating func removeConfirmedDeletedChat(_ key: DraftKey) {
    skillSelections?.removeValue(forKey:key)
    drafts.removeValue(forKey: key)
    pending.removeValue(forKey: key)
    uncertain.remove(key)
    if selected == key { selected = nil }
  }
  public mutating func checkedConversation(_ key: DraftKey) {
    guard uncertain.contains(key) else { return }
    uncertain.remove(key)
    pending.removeValue(forKey: key)
  }
}
