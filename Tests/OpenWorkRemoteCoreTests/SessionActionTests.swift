import Foundation
import Testing

@testable import OpenWorkRemoteCore

private actor ActionTransport: HTTPTransport {
  var requests: [URLRequest] = []
  var wrong = false
  var lose = false
  func configure(wrong: Bool = false, lose: Bool = false) {
    self.wrong = wrong
    self.lose = lose
  }
  func captured() -> [URLRequest] { requests }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    if lose { throw RemoteError.unavailable }
    let b = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let sid = request.url!.path.hasSuffix("/delete") ? "chat" : "child"
    return (
      try JSONSerialization.data(withJSONObject: [
        "data": [
          "requestId": b["requestId"]!, "resourceId": wrong ? "chat" : sid, "state": "accepted",
          "observedAt": "2026-10-09T00:00:00.000Z",
        ], "cursor": NSNull(),
      ]), 200
    )
  }
}
@Suite struct SessionActionTests {
  @Test func previewRejectsExtraFieldsAndContradictoryAvailability() throws {
    let base: [String: Any] = [
      "revision": String(repeating: "a", count: 64), "title": "Synthetic", "running": false,
      "forkAvailable": true, "deleteAvailable": true, "deleteReason": NSNull(),
    ]
    _ = try JSONDecoder().decode(
      SessionActionPreview.self, from: JSONSerialization.data(withJSONObject: base))
    for extra in [
      ["path": "/foreign"], ["deleteReason": "linkedChats"], ["running": true], ["revision": "bad"],
    ] as [[String: Any]] {
      let b = base.merging(extra) { _, new in new }
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(
          SessionActionPreview.self, from: JSONSerialization.data(withJSONObject: b))
      }
    }
  }
  @Test func writesUseClosedBodiesAndOneStableUUID() async throws {
    let t = ActionTransport()
    let client = try BridgeClient(
      origin: URL(string: "https://fixture.test:9443")!, token: "synthetic", transport: t)
    let rid = UUID()
    let revision = String(repeating: "a", count: 64)
    for action in [
      SessionAction.fork(beforeMessageId: nil), .fork(beforeMessageId: "msg_first"), .delete,
    ] {
      _ = try await client.sessionAction(
        "owned", "chat", action: action, revision: revision, requestId: rid)
    }
    let r = await t.captured()
    #expect(r.count == 3)
    #expect(r.map(\.httpMethod) == ["POST", "POST", "POST"])
    let whole = try JSONSerialization.jsonObject(with: r[0].httpBody!) as! [String: Any]
    #expect(whole["beforeMessageId"] is NSNull)
    #expect(Set(whole.keys) == ["revision", "requestId", "beforeMessageId"])
    let before = try JSONSerialization.jsonObject(with: r[1].httpBody!) as! [String: Any]
    #expect(before["beforeMessageId"] as? String == "msg_first")
    #expect(
      r.allSatisfy {
        $0.url?.host == "fixture.test"
          && $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic"
      })
  }
  @Test func lostRepliesAndInvalidTargetsNeverRetry() async throws {
    let t = ActionTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t)
    await #expect(throws: (any Error).self) {
      try await client.sessionAction(
        "../foreign", "chat", action: .delete, revision: String(repeating: "a", count: 64),
        requestId: UUID())
    }
    #expect(await t.captured().isEmpty)
    await t.configure(lose: true)
    await #expect(throws: RemoteError.unavailable) {
      try await client.sessionAction(
        "owned", "chat", action: .fork(beforeMessageId: nil),
        revision: String(repeating: "a", count: 64), requestId: UUID())
    }
    #expect(await t.captured().count == 1)
  }
  @Test func acceptedForkCannotReturnTheParentAndDeletionRemovesOnlyItsExactDraft() async throws {
    let t = ActionTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t)
    await t.configure(wrong: true)
    await #expect(throws: (any Error).self) {
      try await client.sessionAction(
        "owned", "chat", action: .fork(beforeMessageId: nil),
        revision: String(repeating: "a", count: 64), requestId: UUID())
    }
    let target = DraftKey(hostId: "host", workspaceId: "owned", sessionId: "chat")
    let other = DraftKey(hostId: "other", workspaceId: "owned", sessionId: "chat")
    var state = ConversationState()
    state.select(other)
    state.setDraft("Keep")
    state.select(target)
    state.setDraft("Delete")
    state.removeConfirmedDeletedChat(target)
    #expect(state.selected == nil)
    #expect(state.draft(for: target).isEmpty)
    #expect(state.draft(for: other) == "Keep")
  }
}
