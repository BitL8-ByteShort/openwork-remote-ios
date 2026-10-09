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
@Test func attachmentOnlySendRetainsScopedIDsAndCannotBeRepeatedAfterRelaunch() throws {
  var state = ConversationState()
  state.select(DraftKey(hostId:"host",workspaceId:"ws",sessionId:"chat"))
  let ids = ["att_" + String(repeating:"a",count:32)]
  let intent = try state.beginSend(ready:true,attachmentIds:ids)
  #expect(intent.text.isEmpty); #expect(intent.attachmentIds == ids)
  let restoredIntent = try JSONDecoder().decode(SendIntent.self,from:JSONEncoder().encode(intent))
  #expect(restoredIntent.attachmentIds == ids); #expect(restoredIntent.requestId == intent.requestId)
  var reopened = try JSONDecoder().decode(ConversationState.self,from:JSONEncoder().encode(state))
  reopened.recoverPending()
  #expect(throws:RemoteError.unavailable) { try reopened.beginSend(ready:true,attachmentIds:ids) }
}
