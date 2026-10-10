import Foundation
import Testing

@testable import OpenWorkRemoteCore

private actor SkillTransport: HTTPTransport {
  var requests: [URLRequest] = []
  func captured() -> [URLRequest] { requests }
  func data(for r: URLRequest) async throws -> (Data, Int) {
    requests.append(r)
    let b = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
    return (
      try JSONSerialization.data(withJSONObject: [
        "data": [
          "requestId": b["requestId"]!, "resourceId": "chat", "state": "accepted",
          "observedAt": "2026-10-09T00:00:00Z",
        ]
      ]), 200
    )
  }
}
@Suite struct SkillsTests {
  @Test func selectedSkillsSurviveDurableSendAndUseTheFixedPromptRoute() async throws {
    let id = "skill_" + String(repeating: "a", count: 64)
    let rid = UUID()
    let json: [String: Any] = [
      "key": ["hostId": "host", "workspaceId": "owned", "sessionId": "chat"],
      "text": "Run this task", "requestId": rid.uuidString, "selectedSkillIds": [id],
    ]
    let intent = try JSONDecoder().decode(
      SendIntent.self, from: JSONSerialization.data(withJSONObject: json))
    let transport = SkillTransport()
    let client = try BridgeClient(
      origin: URL(string: "https://fixture.test")!, transport: transport)
    _ = try await client.send(intent)
    let requests = await transport.captured()
    #expect(requests.count == 1)
    #expect(requests[0].url?.path == "/v1/workspaces/owned/sessions/chat/messages")
    let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: Any]
    #expect(body["selectedSkillIds"] as? [String] == [id])
    #expect(body["text"] as? String == "Run this task")
  }
}
@Suite struct SkillDraftSelectionTests {
  @Test func selectionPersistsPerChatAndClearsOnlyAfterMatchingAcceptedSend() throws {
    let a = DraftKey(hostId: "host", workspaceId: "owned", sessionId: "a")
    let b = DraftKey(hostId: "host", workspaceId: "owned", sessionId: "b")
    let id = "skill_" + String(repeating: "a", count: 64)
    var state = ConversationState()
    state.select(a)
    state.setDraft("Task")
    try state.setSelectedSkills([id])
    state.select(b)
    #expect(state.selectedSkills.isEmpty)
    state.select(a)
    let restored = try JSONDecoder().decode(
      ConversationState.self, from: JSONEncoder().encode(state))
    #expect(restored.selectedSkills == [id])
    let intent = try state.beginSend(ready: true)
    #expect(intent.selectedSkillIds == [id])
    state.applyReceipt(intent, accepted: true)
    #expect(state.selectedSkills.isEmpty)
  }
}
