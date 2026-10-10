import Foundation
import OpenWorkRemoteCore
import Testing

@testable import OpenWorkRemoteAppState

private actor SkillStoreTransport: HTTPTransport {
  var posts = 0, grant = true, lost = false, policyDenied = false, lateDenied = false,
    postRace = false, delayed = false, reads = 0, removed = false
  var revision = String(repeating: "a", count: 64), content = "Instructions"
  var moveDirectory: URL?
  var continuation: CheckedContinuation<Void, Never>?
  let id = "skill_" + String(repeating: "b", count: 64)
  func configure(
    grant: Bool = true, lost: Bool = false, policyDenied: Bool = false, lateDenied: Bool = false,
    postRace: Bool = false, delayed: Bool = false
  ) {
    self.grant = grant
    self.lost = lost
    self.policyDenied = policyDenied
    self.lateDenied = lateDenied
    self.postRace = postRace
    self.delayed = delayed
  }
  func failPersistenceAfterPost(_ url: URL) { moveDirectory = url }
  func counts() -> (Int, Int) { (posts, reads) }
  func release() {
    continuation?.resume()
    continuation = nil
  }
  func data(for r: URLRequest) async throws -> (Data, Int) {
    let path = r.url!.path
    let value: Any
    if path == "/v1/device/access" {
      value = [
        "allWorkspaces": false, "workspaceIds": ["owned"],
        "features": ["workspaceAdministration": grant],
      ]
    } else if r.httpMethod == "POST" {
      posts += 1
      if policyDenied { return (Data("{\"error\":{\"code\":\"SKILL_WRITE_DENIED\"}}".utf8), 422) }
      let b = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
      let written = String(repeating: "d", count: 64)
      revision = postRace ? String(repeating: "e", count: 64) : written
      if path.hasSuffix("/delete") { removed = true } else { content = b["content"] as! String }
      if lost { throw RemoteError.unavailable }
      if lateDenied { return (Data(), 403) }
      var receipt: [String: Any] = [
        "requestId": b["requestId"]!, "resourceId": id, "state": "accepted",
        "observedAt": "2026-10-09T00:00:00Z",
      ]
      if !removed { receipt["resourceRevision"] = written }
      value = receipt
    } else {
      if posts > 0, let directory = moveDirectory {
        try FileManager.default.moveItem(
          at: directory, to: directory.appendingPathExtension("retained"))
        moveDirectory = nil
      }
      reads += 1
      if delayed { await withCheckedContinuation { continuation = $0 } }
      let item: [String: Any] = [
        "id": id, "name": "owned-skill", "description": "Synthetic", "source": "workspace",
        "editable": true, "selectable": true, "revision": revision,
      ]
      if path.hasSuffix(id) {
        value = ["item": item, "content": content]
      } else {
        value = ["items": removed ? [] : [item], "revision": String(repeating: "c", count: 64)]
      }
    }
    return (try JSONSerialization.data(withJSONObject: ["data": value]), 200)
  }
}
@MainActor @Suite struct SkillStoreTests {
  @Test func clearingDraftDuringAnUnconfirmedSaveDoesNotRestoreItsText() async throws {
    let (s, c, t, client, dir) = try await fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try s.beginDraft(detail: nil, context: c)
    try await s.flush()
    await t.configure(postRace: true, delayed: true)
    let action = SkillAction.save(name: "owned-skill", content: "Updated", revision: s.catalog!.items[0].revision,
      catalogRevision: s.catalog!.revision)
    let save = Task { await s.change(action, client: client, context: c) }
    for _ in 0..<100 { if await t.counts().1 == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
    #expect(await t.counts().1 == 2)
    let rid = try #require(s.pending?.requestId)
    try await s.clearUnsentDrafts()
    #expect(s.draft(id:nil,context:c) == nil)
    await t.release()
    #expect(await save.value == false)
    #expect(s.draft(id:nil,context:c) == nil)
    #expect(s.pending?.requestId == rid)
    #expect(s.pending?.phase == .uncertain)
  }
  private func fixture() async throws -> (
    SkillStore, SkillContext, SkillStoreTransport, BridgeClient, URL
  ) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SkillStore(directory: dir)
    try await store.restore()
    let c = SkillContext(hostId: "host", workspaceId: "owned", generation: UUID())
    store.activate(c)
    let t = SkillStoreTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t)
    await store.refresh(client: client, context: c, read: true, write: true)
    return (store, c, t, client, dir)
  }
  @Test func oversizedEncodedRequestIsRejectedBeforeDispatchAndDoesNotBecomeUncertain() async throws
  {
    let (s, c, t, client, dir) = try await fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let action = SkillAction.save(
      name: "owned-skill", content: String(repeating: "x\n", count: 15000),
      revision: s.catalog!.items[0].revision, catalogRevision: s.catalog!.revision)
    #expect(await s.change(action, client: client, context: c) == false)
    #expect(await t.counts().0 == 0)
    #expect(s.pending == nil)
  }
  @Test func missingAdministrationStillShowsCatalogAndPreservesAnUnsentDraft() async throws {
    let (s, c, t, client, dir) = try await fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    await t.configure(grant: false)
    await s.refresh(client: client, context: c, read: true, write: true)
    #expect(s.catalog?.items.count == 1)
    #expect(!s.canEdit)
    let d = try s.beginDraft(detail: nil, context: c)
    try await s.flush()
    #expect(
      await s.change(
        .save(name: d.name, content: d.content, revision: nil, catalogRevision: d.catalogRevision),
        client: client, context: c) == false)
    #expect(await t.counts().0 == 0)
    #expect(s.draft(id: nil, context: c) == d)
  }
  @Test func policyRejectionAndStaleRevisionNeverDiscardTheDraft() async throws {
    let (s, c, t, client, dir) = try await fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let detail = try await s.detail(s.catalog!.items[0].id, client: client, context: c)
    var d = try s.beginDraft(detail: detail, context: c)
    d.content = "Phone draft"
    try s.updateDraft(d, context: c)
    let stale = SkillAction.save(
      name: d.name, content: d.content, revision: String(repeating: "e", count: 64),
      catalogRevision: d.catalogRevision)
    #expect(await s.change(stale, client: client, context: c) == false)
    #expect(await t.counts().0 == 0)
    await t.configure(policyDenied: true)
    #expect(
      await s.change(
        .save(
          name: d.name, content: d.content, revision: d.revision, catalogRevision: d.catalogRevision
        ), client: client, context: c) == false)
    #expect(s.pending == nil)
    #expect(s.draft(id: d.id, context: c)?.content == "Phone draft")
    #expect(await t.counts().0 == 1)
  }
  @Test func lostReceiptSurvivesReopenAndAnotherSaveCannotDispatch() async throws {
    let (s, c, t, client, dir) = try await fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let detail = try await s.detail(s.catalog!.items[0].id, client: client, context: c)
    let d = try s.beginDraft(detail: detail, context: c)
    await t.configure(lost: true)
    let action = SkillAction.save(
      name: d.name, content: d.content, revision: d.revision, catalogRevision: d.catalogRevision)
    #expect(await s.change(action, client: client, context: c) == false)
    #expect(s.pending?.phase == .uncertain)
    #expect(await s.change(action, client: client, context: c) == false)
    #expect(await t.counts().0 == 1)
    let restored = SkillStore(directory: dir)
    try await restored.restore()
    restored.activate(c)
    #expect(restored.pending?.requestId == s.pending?.requestId)
    #expect(restored.pending?.phase == .uncertain)
    #expect(restored.draft(id: d.id, context: c) == d)
  }
  @Test func aLaterDesktopEditCannotConfirmThePhonesWrittenRevision() async throws {
    let (s, c, t, client, dir) = try await fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    await t.configure(postRace: true)
    #expect(
      await s.change(
        .save(
          name: "owned-skill", content: "Phone update", revision: s.catalog!.items[0].revision,
          catalogRevision: s.catalog!.revision), client: client, context: c) == false)
    #expect(s.pending?.phase == .uncertain)
    #expect(await t.counts().0 == 1)
  }
  @Test func anOldCatalogResponseCannotPopulateAnotherHostContext() async throws {
    let (s, c, t, client, dir) = try await fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let originalReads = await t.counts().1
    await t.configure(delayed: true)
    let task = Task { await s.refresh(client: client, context: c, read: true, write: true) }
    for _ in 0..<100 {
      if await t.counts().1 > originalReads { break }
      await Task.yield()
    }
    let other = SkillContext(hostId: "other", workspaceId: "foreign", generation: UUID())
    s.activate(other)
    await t.release()
    await task.value
    #expect(s.context == other)
    #expect(s.catalog == nil)
    #expect(!s.canEdit)
  }
}

@MainActor @Suite struct SkillStoreRecoveryTests {
  @Test func escapedDraftsCannotWriteAFileTooLargeToRestore() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let drafts = (0..<49).map { index -> [String: Any] in
      [
        "hostId": "host", "workspaceId": index == 48 ? "owned" : "other-\(index)",
        "catalogRevision": String(repeating: "c", count: 64), "name": "my-skill",
        "content": String(repeating: "\u{0001}", count: 42500),
      ]
    }
    let file = dir.appending(path: "skills.json")
    let initial = try JSONSerialization.data(withJSONObject: ["drafts": drafts, "intents": []])
    #expect(initial.count < 12 * 1024 * 1024)
    try initial.write(to: file)
    let s = SkillStore(directory: dir)
    try await s.restore()
    let c = SkillContext(hostId: "host", workspaceId: "owned", generation: UUID())
    s.activate(c)
    var d = try #require(s.draft(id: nil, context: c))
    d.content = String(repeating: "\u{0001}", count: 65536)
    try s.updateDraft(d, context: c)
    do {
      try await s.flush()
      Issue.record("An oversized protected snapshot must not be written")
    } catch { #expect(error as? RemoteError == .oversized) }
    #expect(try Data(contentsOf: file).count <= 12 * 1024 * 1024)
  }
  @Test func acceptedWriteWithFailedLocalCleanupRetainsOneUncertainIntentInMemoryAndOnDisk()
    async throws
  {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let s = SkillStore(directory: dir)
    try await s.restore()
    defer {
      try? FileManager.default.removeItem(at: dir)
      try? FileManager.default.removeItem(at: dir.appendingPathExtension("retained"))
    }
    let c = SkillContext(hostId: "host", workspaceId: "owned", generation: UUID())
    s.activate(c)
    let t = SkillStoreTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t)
    await s.refresh(client: client, context: c, read: true, write: true)
    await t.failPersistenceAfterPost(dir)
    let ok = await s.change(
      .save(
        name: "owned-skill", content: "Updated", revision: s.catalog!.items[0].revision,
        catalogRevision: s.catalog!.revision), client: client, context: c)
    #expect(!ok)
    #expect(s.pending != nil)
    #expect(s.pending?.phase == .uncertain)
    #expect(!s.ready)
    #expect(await t.counts().0 == 1)
    let rid = s.pending?.requestId
    try FileManager.default.moveItem(at: dir.appendingPathExtension("retained"), to: dir)
    let restored = SkillStore(directory: dir)
    try await restored.restore()
    restored.activate(c)
    #expect(restored.pending?.requestId == rid)
    #expect(restored.pending?.phase == .uncertain)
    #expect(await t.counts().0 == 1)
  }
}
