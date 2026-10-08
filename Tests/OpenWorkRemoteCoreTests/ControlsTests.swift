import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Test func clearingReasoningSendsExplicitNullAndPreservesProvider() throws {
  let selection = ModelSelection(providerId: "configured", modelId: "model-a", variant: nil)
  let data = try JSONEncoder().encode(selection)
  let value = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(value["variant"] is NSNull)
  #expect(value["providerId"] as? String == "configured")
}
@Test func compactActivityKeepsTextAfterToolsVisible() throws {
  let data = Data(#"{"id":"combined","sessionId":"s","role":"assistant","createdAt":"now","blocks":[{"kind":"tool","name":"check","status":"completed"},{"kind":"text","text":"The final answer."}],"state":"complete"}"#.utf8)
  let message = try JSONDecoder().decode(ChatMessage.self, from: data)
  let items = ConversationPresentation.items([message], compact: true)
  #expect(items.count == 2)
  #expect(items.first?.isActivity == true)
  #expect(items.last?.isActivity == false)
  #expect(items.last?.messages.first?.blocks.first?.text == "The final answer.")
}
@Test func compactActivityKeepsFinalAnswerAndUserTurnOrder() throws {
  func message(_ id: String, _ role: String, tool: Bool) throws -> ChatMessage {
    let blocks: [[String: Any]] = tool ? [["kind": "text", "text": "Checking…"], ["kind": "tool", "name": "check", "status": "completed", "summary": "Done"]] : [["kind": "text", "text": "Visible answer"]]
    return try JSONDecoder().decode(ChatMessage.self, from: JSONSerialization.data(withJSONObject: ["id": id, "sessionId": "s", "role": role, "createdAt": "now", "blocks": blocks, "state": "complete"]))
  }
  let messages = try [message("user", "user", tool: false), message("step1", "assistant", tool: true), message("step2", "assistant", tool: true), message("answer", "assistant", tool: false), message("next", "user", tool: false)]
  let compact = ConversationPresentation.items(messages, compact: true)
  #expect(compact.map(\.id) == ["user", "activity:step1", "answer", "next"])
  #expect(compact[1].messages.map(\.id) == ["step1", "step2"])
  #expect(compact[1].toolCount == 2)
  #expect(ConversationPresentation.items(messages, compact: false).map(\.id) == messages.map(\.id))
}
