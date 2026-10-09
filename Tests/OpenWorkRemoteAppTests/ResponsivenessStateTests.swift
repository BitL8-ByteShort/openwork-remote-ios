import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor SelectionTransport: HTTPTransport {
  var pending: [String: CheckedContinuation<(Data, Int), any Error>] = [:]
  var pendingAccess: CheckedContinuation<(Data, Int), any Error>?
  func waitForAccess() async throws {
    for _ in 0..<100 {
      if pendingAccess != nil { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw RemoteError.unavailable
  }
  func completeAccess() {
    pendingAccess?.resume(returning: (Data(#"{"data":{"allWorkspaces":true,"workspaceIds":[],"features":{"fileTransfer":true,"workspaceAdministration":true,"automationManagement":true}},"cursor":null}"#.utf8),200))
    pendingAccess = nil
  }
  func waitForPending(_ id: String) async throws {
    for _ in 0..<100 {
      if pending[id] != nil { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw RemoteError.unavailable
  }
  func complete(_ id: String, status: Int) {
    pending.removeValue(forKey: id)?.resume(returning: (Data("{\"data\":[],\"cursor\":null}".utf8), status))
  }
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error> {
    AsyncThrowingStream { _ in }
  }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    let path = request.url!.path
    if path.hasSuffix("/device/access") {
      return try await withCheckedThrowingContinuation { pendingAccess = $0 }
    }
    if path.hasSuffix("/messages") {
      let id = path.split(separator: "/").dropLast().last!.description
      return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    let object: Any
    let host = ["hostId":"fixture", "displayName":"Synthetic", "platform":"linux", "architecture":"x64", "runtimeKind":"desktop", "protocolVersion":1, "upstreamVersion":"0.18.57", "compatibility":"supported", "capabilities":["readSessions":true,"readMessages":true,"readStatus":true,"events":true,"createSession":false,"sendText":false,"stop":false,"readApprovals":true,"replyApproval":false,"maxPromptBytes":32768,"protocolVersion":1]] as [String: Any]
    if path.hasSuffix("/host") { object = host }
    else if path.hasSuffix("/pairings/claim") { object = ["claimId":"synthetic-claim","pollToken":"synthetic-poll","expiresAt":"later"] }
    else if path.hasSuffix("/pairings/poll") { object = ["state":"approved","credential":"new-synthetic-credential","host":host,"allowedWorkspaces":["workspace"]] as [String: Any] }
    else if path.hasSuffix("/workspaces") { object = [["id":"workspace", "name":"Synthetic"]] }
    else if path.hasSuffix("/sessions") { object = [] as [String] }
    else if path.hasSuffix("/status") { object = ["phase":"idle", "observedAt":"now"] }
    else { object = [] as [String] }
    return (try JSONSerialization.data(withJSONObject: ["data":object,"cursor":NSNull()]),200)
  }
}

@Suite @MainActor struct ResponsivenessStateTests {
  private func connected(_ transport: SelectionTransport) async throws -> AppModel {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let model = AppModel(pairingPersistence: PairingPersistence(load: {
      StoredPairing(origin:"https://fixture.example.test",token:"synthetic",hostId:"fixture")
    }, save:{ _ in },remove:{}),transport:transport,draftStore:try DraftStore(directory:directory))
    await model.start()
    for _ in 0..<100 {
      if model.connection == .ready { return model }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw RemoteError.unavailable
  }
  private func session(_ id: String) throws -> ChatSession {
    try JSONDecoder().decode(ChatSession.self, from: JSONSerialization.data(withJSONObject:
      ["id":id,"workspaceId":"workspace","title":id,"updatedAt":"now","status":"idle"]))
  }
  @Test func lateFailedReadCannotReplaceAnotherChatsNotice() async throws {
    let transport = SelectionTransport(), model = try await connected(transport)
    defer { model.sceneActive(false) }
    let first = Task { await model.select(try! session("first")) }
    try await transport.waitForPending("first")
    let second = Task { await model.select(try! session("second")) }
    try await transport.waitForPending("second")
    await transport.complete("second", status:200)
    await second.value
    model.notice = "Notice for the current chat"
    await transport.complete("first", status:503)
    await first.value
    #expect(model.selectedSession?.id == "second")
    #expect(model.notice == "Notice for the current chat")
  }
  @Test func lateReadCannotEndAnotherChatsLoadingState() async throws {
    let transport = SelectionTransport(), model = try await connected(transport)
    defer { model.sceneActive(false) }
    let first = Task { await model.select(try! session("first")) }
    try await transport.waitForPending("first")
    let second = Task { await model.select(try! session("second")) }
    try await transport.waitForPending("second")
    await transport.complete("first", status:200)
    await first.value
    let stillLoading = model.loading
    await transport.complete("second", status:200)
    await second.value
    #expect(stillLoading)
    #expect(model.selectedSession?.id == "second")
    #expect(!model.loading)
  }
  @Test func lateReplyAfterRePairIgnored() async throws {
    let transport = SelectionTransport(), model = try await connected(transport)
    defer { model.sceneActive(false) }
    let oldReply = Task { try await model.loadDeviceAccess() }
    try await transport.waitForAccess()
    await model.forget()
    model.pair(#"{"protocolVersion":1,"origin":"https://fixture.example.test","pairingId":"6aaf91c4-f75b-4c4c-a18e-8914e58d9f05","secret":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#)
    for _ in 0..<200 {
      if model.connection == .ready { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.connection == .ready)
    // The same host/workspace strings must not make an old credential's reply current.
    #expect(model.host?.hostId == "fixture")
    await transport.completeAccess()
    do {
      _ = try await oldReply.value
      Issue.record("A reply from the previous pairing must not become current grants")
    } catch { #expect(error as? RemoteError == .cancelled) }
    #expect(model.connection == .ready)
  }
}
