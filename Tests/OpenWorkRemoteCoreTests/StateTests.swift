import Foundation
import Testing

@testable import OpenWorkRemoteCore

@Test func changingChatCannotRedirectASendOrClearAnotherDraft() throws {
  var state = ConversationState()
  let first = DraftKey(hostId: "host-one", workspaceId: "ws", sessionId: "same")
  let second = DraftKey(hostId: "host-two", workspaceId: "ws", sessionId: "same")
  state.select(first)
  state.setDraft("First text")
  let intent = try state.beginSend(ready: true)
  state.select(second)
  state.setDraft("Second text")
  state.applyReceipt(intent, accepted: true)
  #expect(intent.key == first)
  #expect(state.currentDraft == "Second text")
  #expect(state.draft(for: first) == "")
}
@Test func uncertainSendRetainsItsDraftAndCannotBeAutomaticallyRepeated() throws {
  var state = ConversationState()
  let key = DraftKey(hostId: "host", workspaceId: "ws", sessionId: "chat")
  state.select(key)
  state.setDraft("Keep this")
  let intent = try state.beginSend(ready: true)
  state.applyReceipt(intent, accepted: false)
  #expect(state.currentDraft == "Keep this")
  #expect(state.uncertain.contains(key))
  #expect(throws: (any Error).self) { try state.beginSend(ready: true) }
}
