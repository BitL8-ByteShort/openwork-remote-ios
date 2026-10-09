import Foundation
import OpenWorkRemoteCore
import Testing

@testable import OpenWorkRemoteAppState

private actor GroupsTransport: HTTPTransport {
  private var postCount = 0, readCount = 0, loss = false, stale = false, denied = false,
    delayed = false
  private var wrongResource = false
  private var continuation: CheckedContinuation<Void, Never>?
  func configure(
    loss: Bool = false, stale: Bool = false, denied: Bool = false, delayed: Bool = false,
    wrongResource: Bool = false
  ) {
    self.wrongResource = wrongResource
    self.loss = loss
    self.stale = stale
    self.denied = denied
    self.delayed = delayed
  }
  func counts() -> (Int, Int) { (postCount, readCount) }
  func release() {
    continuation?.resume()
    continuation = nil
  }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    let value: Any
    if request.url!.path == "/v1/device/access" {
      value = [
        "allWorkspaces": false, "workspaceIds": denied ? [] : ["owned"],
        "features": [
          "fileTransfer": false, "workspaceAdministration": false, "automationManagement": false,
        ],
      ]
    } else if request.httpMethod == "POST" {
      postCount += 1
      if loss { throw RemoteError.unavailable }
      if stale { return (Data(), 409) }
      let b = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      value = [
        "requestId": b["requestId"]!, "resourceId": wrongResource ? "other" : "first",
        "state": "accepted", "observedAt": "2026-10-09T00:00:00.000Z",
      ]
    } else {
      readCount += 1
      if delayed { await withCheckedContinuation { continuation = $0 } }
      value = [
        "revision": String(repeating: "a", count: 64),
        "groups": [["id": "first", "label": "First"]], "assignments": ["chat": "first"],
      ]
    }
    return (try JSONSerialization.data(withJSONObject: ["data": value, "cursor": NSNull()]), 200)
  }
}
@MainActor @Suite struct GroupStoreTests {
  private func setup() async throws -> (
    GroupStore, GroupContext, GroupsTransport, BridgeClient, URL
  ) {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = GroupStore(directory: folder)
    try await store.restore()
    let c = GroupContext(hostId: "fixture", workspaceId: "owned", generation: UUID())
    store.activate(c)
    let t = GroupsTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t)
    await store.refresh(client: client, context: c, supported: true)
    return (store, c, t, client, folder)
  }
  @Test func unsupportedOrRevokedProjectNeverReadsOrWritesGroups() async throws {
    let (s, c, t, client, folder) = try await setup()
    defer { try? FileManager.default.removeItem(at: folder) }
    s.activate(nil)
    s.activate(c)
    await s.refresh(client: client, context: c, supported: false)
    #expect(s.availability == .unsupported)
    await t.configure(denied: true)
    await s.refresh(client: client, context: c, supported: true)
    #expect(s.snapshot == nil)
    #expect(await s.mutate(.rename(id: "first", label: "New"), client: client, context: c) == false)
    #expect(await t.counts().0 == 0)
  }
  @Test func lostMutationIsDurableAndRestoreNeverAutomaticallyResends() async throws {
    let (s, c, t, client, folder) = try await setup()
    defer { try? FileManager.default.removeItem(at: folder) }
    await t.configure(loss: true)
    #expect(await s.mutate(.rename(id: "first", label: "New"), client: client, context: c) == false)
    let original = try #require(s.pending?.requestId)
    #expect(s.pending?.phase == .uncertain)
    let restored = GroupStore(directory: folder)
    try await restored.restore()
    restored.activate(c)
    #expect(restored.pending?.requestId == original)
    await restored.refresh(client: client, context: c, supported: true)
    #expect(
      await restored.mutate(.rename(id: "first", label: "New"), client: client, context: c) == false
    )
    #expect(await t.counts().0 == 1)
    try await restored.keepCurrentGroups(context: c)
    #expect(restored.pending == nil)
  }
  @Test func staleRenameRequiresRefreshAndDoesNotClaimSuccess() async throws {
    let (s, c, t, client, folder) = try await setup()
    defer { try? FileManager.default.removeItem(at: folder) }
    await t.configure(stale: true)
    #expect(await s.mutate(.rename(id: "first", label: "New"), client: client, context: c) == false)
    #expect(s.needsRefresh)
    #expect(s.pending == nil)
    #expect(s.snapshot?.groups.first?.label == "First")
    #expect(await t.counts().0 == 1)
  }
  @Test func lateReadCannotReplaceAnotherHostOrWorkspace() async throws {
    let (s, c, t, client, folder) = try await setup()
    defer { try? FileManager.default.removeItem(at: folder) }
    await t.configure(delayed: true)
    let read = Task { await s.refresh(client: client, context: c, supported: true) }
    for _ in 0..<100 {
      if await t.counts().1 == 2 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let next = GroupContext(hostId: "another", workspaceId: "owned", generation: UUID())
    s.activate(next)
    await t.release()
    await read.value
    #expect(s.context == next)
    #expect(s.snapshot == nil)
    #expect(s.notice == nil)
  }
  @Test func sameIntentCannotBeConfirmedFromAnAcceptedReplyForAnotherTarget() async throws {
    let (s, c, t, client, folder) = try await setup()
    defer { try? FileManager.default.removeItem(at: folder) }
    await t.configure(wrongResource: true)
    #expect(await s.mutate(.rename(id: "first", label: "New"), client: client, context: c) == false)
    #expect(s.pending?.phase == .uncertain)
    #expect(await t.counts().0 == 1)
  }
}
extension GroupStoreTests {
  @Test func capabilityWithdrawalDuringAReadClearsLoadingAndDiscardsTheLateSnapshot() async throws {
    let (s, c, t, client, folder) = try await setup()
    defer { try? FileManager.default.removeItem(at: folder) }
    await t.configure(delayed: true)
    let read = Task { await s.refresh(client: client, context: c, supported: true) }
    for _ in 0..<100 {
      if await t.counts().1 == 2 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    await s.refresh(client: client, context: c, supported: false)
    #expect(!s.loading)
    await t.release()
    await read.value
    #expect(s.snapshot == nil)
    #expect(s.availability == .unsupported)
  }
}

extension GroupStoreTests {
  @Test func anOlderOpenFormCannotUseAPolledRevisionToOverwriteNewerGroups() async throws {
    let (s, c, t, client, folder) = try await setup()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(
      await s.mutate(
        .rename(id: "first", label: "New"), client: client, context: c,
        expectedRevision: String(repeating: "b", count: 64)) == false)
    #expect(await t.counts().0 == 0)
    #expect(s.pending == nil)
    #expect(s.notice?.contains("form was open") == true)
  }
}
