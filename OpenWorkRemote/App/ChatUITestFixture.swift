#if DEBUG
import Foundation
import OpenWorkRemoteCore

// Isolated synthetic data only; native tests never load or change a real pairing.
@MainActor func chatUITestFixture(slowMessages: Bool, failRename: Bool, largeConversation: Bool = false,
  burstEvents: Bool = false, offlineReconnect: Bool = false) -> AppModel {
  let folder = FileManager.default.temporaryDirectory.appending(path: "chat-ui-" + UUID().uuidString)
  return AppModel(pairingPersistence: PairingPersistence(load: {
    StoredPairing(origin: "https://fixture.example.test", token: "synthetic", hostId: "fixture-host")
  }, save: { _ in }, remove: {}), transport: ChatUITestTransport(slowMessages: slowMessages, failRename: failRename,
    largeConversation: largeConversation, burstEvents: burstEvents, offlineReconnect: offlineReconnect),
    draftStore: try? DraftStore(directory: folder))
}
private actor ChatUITestTransport: HTTPTransport {
  let slowMessages: Bool
  let failRename: Bool
  let largeConversation: Bool
  let burstEvents: Bool
  let offlineReconnect: Bool
  var connections = 0
  var title = "Sample chat"
  init(slowMessages: Bool, failRename: Bool, largeConversation: Bool, burstEvents: Bool, offlineReconnect: Bool) {
    self.slowMessages = slowMessages; self.failRename = failRename
    self.largeConversation = largeConversation; self.burstEvents = burstEvents; self.offlineReconnect = offlineReconnect
  }
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error> {
    connections += 1
    if offlineReconnect && connections <= 2 { throw RemoteError.unavailable }
    let burst = burstEvents
    return AsyncThrowingStream { continuation in
      guard burst else { return }
      let task = Task {
        for i in 0..<6_000 {
          do { try await Task.sleep(for: .milliseconds(50)); try Task.checkCancellation() }
          catch { break }
          continuation.yield(SSEFrame(event: "change", id: "synthetic-\(i)",
            data: "{\"kind\":\"message\",\"workspaceId\":\"ws_test\",\"sessionId\":\"ses_test\"}"))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
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
      let messages: [[String: Any]] = largeConversation ? (0..<500).map { i in
        let blocks: [[String: Any]] = i % 10 == 0
          ? [["kind": "tool", "name": "synthetic_check", "status": "completed", "summary": "Synthetic activity"]]
          : [["kind": "text", "text": "Large conversation fixture \(i)"],
             ["kind": "text", "text": String(repeating: "A synthetic **Markdown** paragraph with a [sample link](https://example.test).\n\n", count: 12) + "```swift\nlet fixture = true\n```"]]
        return ["id": String(format: "msg_%04d", i), "sessionId": "ses_test", "role": "assistant",
          "createdAt": "2026-10-08T12:00:00Z", "blocks": blocks, "state": "complete"]
      } : []
      return try response(messages)
    }
    if path.hasSuffix("/status") { return try response(["phase": "idle", "observedAt": "now"]) }
    if path.hasSuffix("/approvals") { return try response([]) }
    if path.hasSuffix("/access") {
      return try response(["allWorkspaces": false, "workspaceIds": ["ws_test"],
        "features": ["fileTransfer": true, "workspaceAdministration": false, "automationManagement": false]])
    }
    if path.hasSuffix("/permissions") {
      return try response(["grants": [], "modeSupported": false,
        "modeReason": "Approval mode changes are unavailable on this computer."])
    }
    return try response(session)
  }
  private func response(_ value: Any) throws -> (Data, Int) {
    (try JSONSerialization.data(withJSONObject: ["data": value, "cursor": NSNull()]), 200)
  }
}
#endif
