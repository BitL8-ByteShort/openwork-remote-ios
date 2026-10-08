#if DEBUG
import Foundation
import OpenWorkRemoteCore

// Isolated synthetic data only; native tests never load or change a real pairing.
@MainActor func chatUITestFixture(slowMessages: Bool, failRename: Bool) -> AppModel {
  let folder = FileManager.default.temporaryDirectory.appending(path: "chat-ui-" + UUID().uuidString)
  return AppModel(pairingPersistence: PairingPersistence(load: {
    StoredPairing(origin: "https://fixture.example.test", token: "synthetic", hostId: "fixture-host")
  }, save: { _ in }, remove: {}), transport: ChatUITestTransport(slowMessages: slowMessages, failRename: failRename),
    draftStore: try? DraftStore(directory: folder))
}
private actor ChatUITestTransport: HTTPTransport {
  let slowMessages: Bool
  let failRename: Bool
  var title = "Sample chat"
  init(slowMessages: Bool, failRename: Bool) { self.slowMessages = slowMessages; self.failRename = failRename }
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error> {
    AsyncThrowingStream { _ in }
  }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    let path = request.url!.path
    if path.hasSuffix("/rename") {
      if failRename { return (Data("{}".utf8), 503) }
      let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
      title = body["title"]!
      return try response(["requestId": body["requestId"]!, "resourceId": "ses_test", "state": "accepted", "observedAt": "now"])
    }
    if path.hasSuffix("/host") {
      return try response(["hostId": "fixture-host", "displayName": "Test computer", "platform": "linux", "architecture": "x64", "runtimeKind": "desktop", "protocolVersion": 1, "upstreamVersion": "0.18.57", "compatibility": "supported", "capabilities": ["readSessions": true, "readMessages": true, "readStatus": true, "events": true, "createSession": false, "sendText": false, "stop": false, "readApprovals": true, "replyApproval": false, "renameSession": true, "maxPromptBytes": 32768, "protocolVersion": 1]])
    }
    if path.hasSuffix("/workspaces") { return try response([["id": "ws_test", "name": "Test project"]]) }
    let session: [String: Any] = ["id": "ses_test", "workspaceId": "ws_test", "title": title, "updatedAt": "2026-10-08", "status": "idle"]
    if path.hasSuffix("/sessions") { return try response([session]) }
    if path.hasSuffix("/messages") {
      if slowMessages { try await Task.sleep(for: .seconds(30)) }
      return try response([])
    }
    if path.hasSuffix("/status") { return try response(["phase": "idle", "observedAt": "now"]) }
    if path.hasSuffix("/approvals") { return try response([]) }
    return try response(session)
  }
  private func response(_ value: Any) throws -> (Data, Int) {
    (try JSONSerialization.data(withJSONObject: ["data": value, "cursor": NSNull()]), 200)
  }
}
#endif
