import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor UploadTestTransport: HTTPTransport {
  var file: [String: Any]?
  var allocationIDs: [String] = []
  var offsets: [Int] = []
  var commits: [String] = []
  var cancels: [String] = []
  var loseAllocation = false, loseChunk = false, loseCommit = false, waitCommit = false
  var corruptProgress = false
  func corruptChunkProgress() { corruptProgress = true }
  var continuation: CheckedContinuation<Void, Never>?
  func configure(allocation: Bool = false, chunk: Bool = false, commit: Bool = false, wait: Bool = false) {
    loseAllocation = allocation; loseChunk = chunk; loseCommit = commit; waitCommit = wait
  }
  func counts() -> ([String], [Int], [String], [String]) { (allocationIDs, offsets, commits, cancels) }
  func release() { continuation?.resume(); continuation = nil }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    let path = request.url!.path
    let body = request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream"
      ? [:] : (try request.httpBody.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] } ?? [:])
    if path.hasSuffix("/access") { return try envelope(["allWorkspaces":false,"workspaceIds":["ws_test"],"features":["fileTransfer":true]]) }
    if path.hasSuffix("/limits") { return try envelope(["maxFileBytes":20_971_520,"inputMIMEs":["image/png","application/pdf"]]) }
    if path.hasSuffix("/attachments") {
      let uuid = body["requestId"] as! String; allocationIDs.append(uuid)
      if file == nil {
        file = ["id":"att_" + String(repeating:"1",count:32),"name":body["name"]!,"mime":body["mime"]!,
          "bytes":body["bytes"]!,"sha256":body["sha256"]!,"receivedBytes":0,"state":"uploading"]
      }
      if loseAllocation { loseAllocation = false; throw RemoteError.unavailable }
      return try mutation(uuid)
    }
    if path.hasSuffix("/chunks") {
      let offset = Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first!.value!)!
      offsets.append(offset); file!["receivedBytes"] = offset + request.httpBody!.count
      if corruptProgress { file!["receivedBytes"] = offset + request.httpBody!.count - 1 }
      if loseChunk { loseChunk = false; throw RemoteError.unavailable }
      return try envelope(file!)
    }
    if path.hasSuffix("/commit") {
      let uuid = body["requestId"] as! String; commits.append(uuid)
      if waitCommit { await withCheckedContinuation { continuation = $0 } }
      file!["state"] = "ready"
      if loseCommit { throw RemoteError.unavailable }
      return try mutation(uuid)
    }
    if path.hasSuffix("/cancel") {
      let uuid = body["requestId"] as! String; cancels.append(uuid); file!["state"] = "cancelled"
      return try mutation(uuid)
    }
    return try envelope(file!)
  }
  private func mutation(_ uuid: String) throws -> (Data, Int) {
    try envelope(["receipt":["requestId":uuid,"state":"accepted","resourceId":file!["id"]!,"observedAt":"now"],"attachment":file!])
  }
  private func envelope(_ value: Any) throws -> (Data, Int) {
    (try JSONSerialization.data(withJSONObject:["data":value,"cursor":NSNull()]),200)
  }
}

@MainActor @Suite struct AttachmentStoreTests {
  private func context(host: String = "fixture", session: String = "ses_test") -> AttachmentContext {
    AttachmentContext(key:DraftKey(hostId:host,workspaceId:"ws_test",sessionId:session),generation:UUID(),selection:UUID())
  }
  private func setup(_ folder: URL, count: Int = 100) async throws -> (AttachmentStore, LocalAttachmentFile, UploadTestTransport, BridgeClient, AttachmentContext) {
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let selected = folder.appending(path:"selected.pdf")
    try Data(("%PDF-1.7\n" + String(repeating:"x",count:count) + "\n%%EOF\n").utf8).write(to:selected)
    let store = AttachmentStore(directory:folder), file = try await store.files.importPDF(selected)
    let transport = UploadTestTransport(), client = try BridgeClient(origin:URL(string:"https://fixture.example.test")!,transport:transport), c = context()
    try await store.restore(); store.activate(c)
    await store.refreshAccess(client:client,context:c,supported:true)
    try await store.add(file,context:c)
    return (store,file,transport,client,c)
  }
  @Test func allocationReplyLossRetainsUUIDAndDraftAcrossRelaunch() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    await transport.configure(allocation:true)
    await store.upload(file.id,client:client,context:c)
    #expect(store.rows.first?.phase == .failed); #expect(!store.canSend)
    let reopened = AttachmentStore(directory:folder); try await reopened.restore(); reopened.activate(c)
    await reopened.refreshAccess(client:client,context:c,supported:true)
    await reopened.upload(file.id,client:client,context:c)
    let counts = await transport.counts()
    #expect(counts.0.count == 2); #expect(Set(counts.0).count == 1)
    #expect(counts.2.count == 1); #expect(reopened.canSend)
    #expect(reopened.rows.first?.phase == .ready)
  }
  @Test func lostChunkReplyResumesFromHostProgressWithoutSendingAgain() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder,count:1_048_590)
    await transport.configure(chunk:true)
    await store.upload(file.id,client:client,context:c)
    await store.upload(file.id,client:client,context:c)
    #expect(await transport.counts().1 == [0,1_048_576])
    #expect(store.canSend); #expect(store.rows.first?.receivedBytes == file.bytes)
  }
  @Test func lostCommitNeverForwardsAgainAndReadbackCanRecoverReady() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    await transport.configure(commit:true)
    await store.upload(file.id,client:client,context:c)
    #expect(store.rows.first?.phase == .uncertain)
    await store.upload(file.id,client:client,context:c)
    #expect(await transport.counts().2.count == 1)
    let reopened = AttachmentStore(directory:folder); try await reopened.restore(); reopened.activate(c)
    await reopened.refreshAccess(client:client,context:c,supported:true)
    await reopened.check(file.id,client:client,context:c)
    #expect(reopened.canSend); #expect(await transport.counts().2.count == 1)
  }
  @Test func lateCommitCannotChangeAnotherChatOrPairing() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    await transport.configure(wait:true)
    let task = Task { await store.upload(file.id,client:client,context:c) }
    while await transport.counts().2.isEmpty { await Task.yield() }
    let next = context(host:"other"); store.activate(next)
    await transport.release(); await task.value
    #expect(store.context == next); #expect(store.rows.isEmpty); #expect(store.notice == nil)
    store.activate(c)
    #expect(store.rows.first?.phase == .uncertain)
  }
  @Test func failedIntentPersistenceStopsBeforeNetwork() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    try FileManager.default.removeItem(at:folder.appending(path:"attachments.json"))
    try FileManager.default.createDirectory(at:folder.appending(path:"attachments.json"),withIntermediateDirectories:false)
    await store.upload(file.id,client:client,context:c)
    #expect(await transport.counts().0.isEmpty); #expect(!store.canSend)
  }
  @Test func cancelledDraftRetainsTypedTextAndHasNoSendableFile() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    var conversation = ConversationState(); conversation.select(c.key); conversation.setDraft("Keep this text")
    await store.upload(file.id,client:client,context:c)
    await store.remove(file.id,client:client,context:c)
    #expect(store.rows.isEmpty); #expect(store.attachmentIDs.isEmpty)
    #expect(conversation.currentDraft == "Keep this text")
    #expect(await transport.counts().3.count == 1)
    await #expect(throws:(any Error).self) { try await store.files.verify(file) }
  }
  @Test func concurrentSelectionCannotAddTheSameFileTwice() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,_,_,_,c) = try await setup(folder)
    let file = try await store.files.importPDF(folder.appending(path:"selected.pdf"))
    let a = Task { try await store.add(file,context:c) }, b = Task { try await store.add(file,context:c) }
    let outcomes = [await a.result,await b.result]
    #expect(outcomes.filter { if case .success = $0 { return true }; return false }.count == 1)
    #expect(store.rows.filter { $0.id == file.id }.count == 1)
  }
  @Test func aPromptClaimRemainsUnsendableAfterRelaunchAndReadyReadback() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    await store.upload(file.id,client:client,context:c)
    var conversation = ConversationState(); conversation.select(c.key)
    let intent = try conversation.beginSend(ready:true,attachmentIds:store.attachmentIDs)
    try await store.reserveSend(intent)
    let reopened = AttachmentStore(directory:folder); try await reopened.restore(); reopened.activate(c)
    await reopened.refreshAccess(client:client,context:c,supported:true)
    await reopened.check(file.id,client:client,context:c)
    #expect(reopened.rows.first?.promptID == intent.requestId); #expect(!reopened.canSend)
    await reopened.upload(file.id,client:client,context:c)
    #expect(await transport.counts().2.count == 1)
  }
  @Test func aCorruptProgressReplyCannotCommitOrEnableSend() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    await transport.corruptChunkProgress()
    await store.upload(file.id,client:client,context:c)
    #expect(!store.canSend); #expect(await transport.counts().2.isEmpty)
  }
  @Test func aFifthFileIsRefusedWithoutRemovingTheEarlierDrafts() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,_,_,_,c) = try await setup(folder)
    for _ in 0..<3 { try await store.add(store.files.importPDF(folder.appending(path:"selected.pdf")),context:c) }
    let fifth = try await store.files.importPDF(folder.appending(path:"selected.pdf"))
    await #expect(throws:RemoteError.oversized) { try await store.add(fifth,context:c) }
    #expect(store.rows.count == 4)
  }
  @Test func explicitStatusReviewAllowsRemovalWithoutRepeatingUncertainPrompt() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path:"upload-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let (store,file,transport,client,c) = try await setup(folder)
    await store.upload(file.id,client:client,context:c)
    var conversation = ConversationState(); conversation.select(c.key)
    let intent = try conversation.beginSend(ready:true,attachmentIds:store.attachmentIDs)
    try await store.reserveSend(intent); await store.finishSend(intent,accepted:false)
    await store.remove(file.id,client:client,context:c)
    #expect(store.rows.count == 1)
    await store.check(file.id,client:client,context:c)
    #expect(!store.canSend)
    await store.remove(file.id,client:client,context:c)
    #expect(store.rows.isEmpty); #expect(await transport.counts().3.count == 1)
  }
}
