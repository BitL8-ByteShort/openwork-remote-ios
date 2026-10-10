import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@MainActor private final class ResetPairing {
  var value: StoredPairing? = StoredPairing(origin: "https://fixture.test", token: "synthetic", hostId: "fixture")
  var locked = false
  var persistence: PairingPersistence {
    PairingPersistence(load: { self.value }, save: { self.value = $0 }, remove: {
      if self.locked { throw RemoteError.unavailable }
      self.value = nil
    })
  }
}
private actor ResetTransport: HTTPTransport {
  var requests: [(String, String)] = []
  var offline = false
  var heldPrompt: CheckedContinuation<(Data, Int), any Error>?
  var holdPrompt = false
  func configure(offline: Bool) { self.offline = offline }
  func holdNextPrompt() { holdPrompt = true }
  func hasHeldPrompt() -> Bool { heldPrompt != nil }
  func releasePrompt() { heldPrompt?.resume(throwing: RemoteError.unavailable); heldPrompt = nil }
  func calls() -> [(String, String)] { requests }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append((request.httpMethod!, request.url!.path))
    if holdPrompt, request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
      return try await withCheckedThrowingContinuation { heldPrompt = $0 }
    }
    if offline { throw RemoteError.unavailable }
    return (Data(), 204)
  }
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error> {
    AsyncThrowingStream { $0.finish(throwing: RemoteError.unavailable) }
  }
}

@MainActor @Suite struct DataResetTests {
  private func fixture() throws -> (AppModel, DraftStore, ResetPairing, ResetTransport, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try DraftStore(directory: root), pairing = ResetPairing(), transport = ResetTransport()
    let model = AppModel(pairingPersistence: pairing.persistence, transport: transport, draftStore: store, clearPreferences: {})
    return (model, store, pairing, transport, root)
  }
  @Test func clearDraftsKeepsUncertainIDsAndNeverTouchesHost() async throws {
    let (model, store, _, transport, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    await model.start()
    model.sceneActive(false)
    let key = DraftKey(hostId: "fixture", workspaceId: "workspace", sessionId: "chat")
    model.disk.conversation.select(key)
    model.disk.conversation.setDraft("Private unsent draft")
    let intent = try model.disk.conversation.beginSend(ready: true)
    model.disk.conversation.applyReceipt(intent, accepted: false)
    let before = await transport.calls().count
    #expect(await model.clearLocalDrafts())
    #expect(model.disk.conversation.currentDraft == "")
    #expect(model.disk.conversation.pendingRequestId(for: key) == intent.requestId)
    #expect(try await store.load().conversation.pendingRequestId(for: key) == intent.requestId)
    #expect(await transport.calls().count == before)
  }
  @Test func lockedKeychainAbortsBeforeDestructiveCleanup() async throws {
    let (model, store, pairing, _, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    await model.start()
    model.sceneActive(false)
    model.disk.conversation.select(DraftKey(hostId: "fixture", workspaceId: "workspace", sessionId: "chat"))
    model.disk.conversation.setDraft("Keep this draft")
    try await store.save(model.disk, revision: 100)
    pairing.locked = true
    #expect(await model.resetLocalData() == nil)
    #expect(pairing.value != nil)
    #expect(try await store.load().conversation.currentDraft == "Keep this draft")
    #expect(!model.isRetired)
  }
  @Test func offlineResetDoesNotClaimRemoteRevocationAndRetiresOldWriter() async throws {
    let (model, store, pairing, transport, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    await transport.configure(offline: true)
    await model.start()
    model.sceneActive(false)
    let report = try #require(await model.resetLocalData())
    #expect(pairing.value == nil)
    #expect(model.isRetired)
    #expect(report.localFailures.isEmpty)
    #expect(report.hostRevocation == .unconfirmed)
    #expect(report.summary.contains("Revoke this phone"))
    await #expect(throws: SnapshotStoreError.self) { try await store.save(DiskState(), revision: 200) }
    let fresh = try model.freshAfterReset(report)
    await fresh.start()
    #expect(!fresh.hasPairing)
    #expect(!fresh.isRetired)
    model.draft = "A late old edit"
    #expect(fresh.draft.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "drafts.json").path))
    #expect(await transport.calls().allSatisfy { !$0.1.contains("/sessions/") })
    fresh.sceneActive(false)
  }
  @Test func partialRemovalIsReportedAndUnrecognizedFilesStayUntouched() async throws {
    let (model, _, _, _, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    await model.start()
    model.sceneActive(false)
    let folder = root.appending(path: "AttachmentBytes")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("Keep".utf8).write(to: folder.appending(path: "unrecognized.txt"))
    let report = try #require(await model.resetLocalData())
    #expect(report.localFailures.contains("Selected attachments"))
    #expect(report.summary.contains("could not be removed"))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "unrecognized.txt").path))
  }
  @Test func latePromptResponseCannotWriteIntoTheFreshAppAfterReset() async throws {
    let (old, _, _, transport, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    await old.start()
    old.sceneActive(false)
    old.host = try JSONDecoder().decode(Host.self, from: JSONSerialization.data(withJSONObject: [
      "hostId":"fixture", "displayName":"Synthetic", "platform":"macos", "architecture":"arm64",
      "runtimeKind":"desktop", "protocolVersion":1, "upstreamVersion":"0.18.57", "compatibility":"supported",
      "capabilities":["readSessions":true,"readMessages":true,"readStatus":true,"events":false,
        "createSession":false,"sendText":true,"stop":false,"readApprovals":true,"replyApproval":false,
        "maxPromptBytes":32768,"protocolVersion":1]]))
    old.selectedSession = try JSONDecoder().decode(ChatSession.self, from: JSONSerialization.data(withJSONObject:
      ["id":"chat","workspaceId":"workspace","title":"Synthetic","updatedAt":"now","status":"idle"]))
    old.status = try JSONDecoder().decode(SessionStatus.self, from: Data(#"{"phase":"idle","observedAt":"now"}"#.utf8))
    old.connection = .ready
    let key = DraftKey(hostId:"fixture",workspaceId:"workspace",sessionId:"chat")
    old.disk.conversation.select(key)
    old.draft = "Old private draft"
    await transport.holdNextPrompt()
    let send = Task { await old.send() }
    for _ in 0..<100 { if await transport.hasHeldPrompt() { break }; try await Task.sleep(for: .milliseconds(10)) }
    #expect(await transport.hasHeldPrompt())
    let report = try #require(await old.resetLocalData())
    let fresh = try old.freshAfterReset(report)
    await fresh.start()
    fresh.disk.conversation.select(key)
    fresh.draft = "A new draft"
    await transport.releasePrompt()
    await send.value
    #expect(fresh.draft == "A new draft")
    #expect(fresh.disk.conversation.pendingRequestId(for:key) == nil)
    for _ in 0..<100 {
      if try await DraftStore(directory:root).load().conversation.currentDraft == "A new draft" { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try await DraftStore(directory:root).load().conversation.currentDraft == "A new draft")
    fresh.sceneActive(false)
  }
}
