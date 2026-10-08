import Foundation
import Testing

@testable import OpenWorkRemoteCore

@Test func rebootRetainsRequestIdentityAndBlocksUncertainNewChatUntilReviewed() throws {
  var state = MutationState()
  let key = MutationKey(hostId: "mac", workspaceId: "ws", sessionId: nil, action: .create)
  let id = try state.begin(key)
  var restored = try JSONDecoder().decode(MutationState.self, from: JSONEncoder().encode(state))
  restored.recoverPending()
  #expect(restored.requestId(for: key) == id)
  #expect(restored.requiresReview(key))
  #expect(throws: (any Error).self) { try restored.begin(key) }
  restored.reviewed(key)
  #expect(try restored.begin(key) != id)
}
@Test func uncertainOperationsAreScopedToHostWorkspaceAndChat() throws {
  var state = MutationState()
  let mac = MutationKey(hostId: "mac", workspaceId: "same", sessionId: "same", action: .stop)
  let linux = MutationKey(hostId: "linux", workspaceId: "same", sessionId: "same", action: .stop)
  _ = try state.begin(mac)
  state.finish(mac, accepted: false)
  #expect(!state.requiresReview(linux))
  _ = try state.begin(linux)
  state.finish(linux, accepted: true)
  #expect(state.requiresReview(mac))
  #expect(state.requestId(for: linux) == nil)
}
@Test func latestSnapshotPreservesEarlierHistoryAndEndOfPaging() {
  var history = PagedSnapshot<ChatSession>()
  let first = ChatSession(
    id: "recent", workspaceId: "ws", title: "First", updatedAt: "2", modelLabel: nil, status: "idle"
  )
  let older = ChatSession(
    id: "older", workspaceId: "ws", title: "Earlier", updatedAt: "1", modelLabel: nil,
    status: "idle")
  history.latest([first], cursor: "page2")
  history.older([older, first], cursor: nil)
  let updated = ChatSession(
    id: "recent", workspaceId: "ws", title: "Updated", updatedAt: "3", modelLabel: nil,
    status: "idle")
  history.latest([updated], cursor: "page2")
  #expect(history.rows.count == 2)
  #expect(history.rows.first?.title == "Updated")
  #expect(history.cursor == nil)
}
@Test func pendingSendKeepsItsRequestUUIDAcrossProcessDeath() throws {
  var state = ConversationState()
  state.select(DraftKey(hostId: "mac", workspaceId: "ws", sessionId: "chat"))
  state.setDraft("Retain this")
  let intent = try state.beginSend(ready: true)
  var restored = try JSONDecoder().decode(ConversationState.self, from: JSONEncoder().encode(state))
  restored.recoverPending()
  #expect(restored.pendingRequestId(for: intent.key) == intent.requestId)
  #expect(restored.currentDraft == "Retain this")
  #expect(throws: (any Error).self) { try restored.beginSend(ready: true) }
}
@Test func uncertainApprovalIsIsolatedByRequestAndRevision() throws {
  var state = MutationState()
  let first = MutationKey(hostId: "linux", workspaceId: "ws", sessionId: "chat", action: .approval, approvalId: "per_one", revision: "a")
  let changed = MutationKey(hostId: "linux", workspaceId: "ws", sessionId: "chat", action: .approval, approvalId: "per_one", revision: "b")
  let second = MutationKey(hostId: "linux", workspaceId: "ws", sessionId: "chat", action: .approval, approvalId: "per_two", revision: "a")
  let id = try state.begin(first)
  state.finish(first, accepted: false)
  var restored = try JSONDecoder().decode(MutationState.self, from: JSONEncoder().encode(state))
  restored.recoverPending()
  #expect(restored.requestId(for: first) == id)
  #expect(restored.requiresReview(first))
  #expect(!restored.requiresReview(changed))
  #expect(!restored.requiresReview(second))
}
