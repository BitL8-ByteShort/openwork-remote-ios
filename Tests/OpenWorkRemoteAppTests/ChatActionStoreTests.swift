import Foundation
import OpenWorkRemoteCore
import Testing

@testable import OpenWorkRemoteAppState

private actor ChatActionsTransport: HTTPTransport {
  var writes = 0
  var loss = false
  var denied = false
  var linked = false
  var running = false
  var delayed = false
  var continuation: CheckedContinuation<Void, Never>?
  func configure(
    loss: Bool = false, denied: Bool = false, linked: Bool = false, running: Bool = false,
    delayed: Bool = false
  ) {
    self.loss = loss
    self.denied = denied
    self.linked = linked
    self.running = running
    self.delayed = delayed
  }
  func count() -> Int { writes }
  func waiting() -> Bool { continuation != nil }
  func release() {
    continuation?.resume()
    continuation = nil
  }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    let v: Any
    if request.url!.path == "/v1/device/access" {
      v = [
        "allWorkspaces": false, "workspaceIds": denied ? [] : ["owned"],
        "features": [
          "fileTransfer": false, "workspaceAdministration": false, "automationManagement": false,
        ],
      ]
    } else if request.httpMethod == "POST" {
      writes += 1
      if loss { throw RemoteError.unavailable }
      let b = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      v = [
        "requestId": b["requestId"]!,
        "resourceId": request.url!.path.hasSuffix("/delete") ? "chat" : "child",
        "state": "accepted", "observedAt": "2026-10-09T00:00:00.000Z",
      ]
    } else if request.url!.path.hasSuffix("/sessions") {
      v = []
    } else {
      if delayed { await withCheckedContinuation { continuation = $0 } }
      v =
        [
          "revision": String(repeating: "a", count: 64), "title": "Synthetic", "running": running,
          "forkAvailable": !running, "deleteAvailable": !running && !linked,
          "deleteReason": running ? "running" as Any : linked ? "linkedChats" as Any : NSNull(),
        ] as [String: Any]
    }
    return (try JSONSerialization.data(withJSONObject: ["data": v, "cursor": NSNull()]), 200)
  }
}
@MainActor @Suite struct ChatActionStoreTests {
  private func setup() async throws -> (
    ChatActionStore, ChatActionContext, ChatActionsTransport, BridgeClient, URL
  ) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let s = ChatActionStore(directory: dir)
    try await s.restore()
    let c = ChatActionContext(
      hostId: "fixture", workspaceId: "owned", sessionId: "chat", generation: UUID())
    s.activate(c)
    let t = ChatActionsTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t)
    await s.refresh(client: client, context: c, supported: true)
    return (s, c, t, client, dir)
  }
  @Test func lostForkSurvivesRelaunchAndNeverAutomaticallyResends() async throws {
    let (s, c, t, client, dir) = try await setup()
    defer { try? FileManager.default.removeItem(at: dir) }
    await t.configure(loss: true)
    #expect(
      await s.mutate(
        .fork(beforeMessageId: nil), client: client, context: c,
        expectedRevision: String(repeating: "a", count: 64)) == nil)
    let rid = try #require(s.pending?.requestId)
    let restored = ChatActionStore(directory: dir)
    try await restored.restore()
    restored.activate(c)
    await restored.refresh(client: client, context: c, supported: true)
    #expect(restored.pending?.requestId == rid)
    #expect(
      await restored.mutate(
        .fork(beforeMessageId: nil), client: client, context: c,
        expectedRevision: String(repeating: "a", count: 64)) == nil)
    #expect(await t.count() == 1)
    await restored.reviewChats(client: client, context: c)
    try await restored.keepCurrentChats(context: c)
    #expect(restored.pending == nil)
    #expect(await t.count() == 1)
  }
  @Test func runningLinkedStaleAndRevokedTargetsDoNotWrite() async throws {
    for mode in ["running", "linked", "stale", "denied"] {
      let (s, c, t, client, dir) = try await setup()
      defer { try? FileManager.default.removeItem(at: dir) }
      await t.configure(
        denied: mode == "denied", linked: mode == "linked", running: mode == "running")
      await s.refresh(client: client, context: c, supported: true)
      #expect(
        await s.mutate(
          .delete, client: client, context: c,
          expectedRevision: String(repeating: mode == "stale" ? "b" : "a", count: 64)) == nil)
      #expect(await t.count() == 0)
    }
  }
  @Test func cancellingAFormIsLocalAndAnUncertainDeleteDoesNotClaimSuccess() async throws {
    let (s, c, t, client, dir) = try await setup()
    defer { try? FileManager.default.removeItem(at: dir) }
    s.activate(nil)
    #expect(await t.count() == 0)
    s.activate(c)
    await s.refresh(client: client, context: c, supported: true)
    await t.configure(loss: true)
    #expect(
      await s.mutate(
        .delete, client: client, context: c, expectedRevision: String(repeating: "a", count: 64))
        == nil)
    #expect(s.pending?.phase == .uncertain)
    #expect(s.notice?.contains("could not be confirmed") == true)
  }
  @Test func latePreviewAndAcceptedActionCannotCrossHosts() async throws {
    let (s, c, t, client, dir) = try await setup()
    defer { try? FileManager.default.removeItem(at: dir) }
    await t.configure(delayed: true)
    let read = Task { await s.refresh(client: client, context: c, supported: true) }
    for _ in 0..<100 {
      if await t.waiting() { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let next = ChatActionContext(
      hostId: "another", workspaceId: "owned", sessionId: "chat", generation: UUID())
    s.activate(next)
    await t.release()
    await read.value
    #expect(s.preview == nil)
    #expect(s.context == next)
    #expect(await t.count() == 0)
  }
  @Test func acceptedLeafDeleteHasExactTargetWhileForkHasANewTarget() async throws {
    for action in [SessionAction.delete, .fork(beforeMessageId: nil)] {
      let (s, c, t, client, dir) = try await setup()
      defer { try? FileManager.default.removeItem(at: dir) }
      let actual = await s.mutate(
        action, client: client, context: c, expectedRevision: String(repeating: "a", count: 64))
      #expect(actual == (action == .delete ? "chat" : "child"))
      #expect(s.pending == nil)
      #expect(await t.count() == 1)
    }
  }
  @Test func uncertainDeletionStillBlocksItsExactChatAfterContextInvalidation() async throws {
    let (s,c,t,client,dir) = try await setup()
    defer { try? FileManager.default.removeItem(at: dir) }
    await t.configure(loss: true)
    _ = await s.mutate(.delete,client:client,context:c,expectedRevision:String(repeating:"a",count:64))
    s.activate(nil)
    #expect(s.blocksSending(DraftKey(hostId:c.hostId,workspaceId:c.workspaceId,sessionId:c.sessionId)))
    #expect(!s.blocksSending(DraftKey(hostId:"other",workspaceId:c.workspaceId,sessionId:c.sessionId)))
    #expect(await t.count() == 1)
  }

}
