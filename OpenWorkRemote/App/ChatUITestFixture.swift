#if DEBUG
import Foundation
import OpenWorkRemoteCore

#if targetEnvironment(simulator)
// Opt-in live qualification uses ordinary HTTPS and an isolated temporary store.
// Its ephemeral pairing is never loaded from or saved to the user's Keychain.
@MainActor func liveQuestionUITestFixture() -> AppModel {
  struct Configuration: Decodable {
    let pairing: StoredPairing
    let workspaceId: String
    let sessionId: String
  }
  let folder = FileManager.default.temporaryDirectory.appending(path: "live-questions-" + UUID().uuidString)
  let isolatedStore: DraftStore
  do {
    isolatedStore = try DraftStore(directory: folder)
  } catch {
    // A failed test store must never fall back to the installed app's storage.
    preconditionFailure("The isolated question qualification store could not be created.")
  }
  do {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_QUESTION_UI_CONFIG"] else {
      throw RemoteError.unavailable
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard data.count <= 65536 else { throw RemoteError.invalidResponse }
    let config = try JSONDecoder().decode(Configuration.self, from: data)
    _ = try PairingValidation.origin(config.pairing.origin)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
    var disk = DiskState()
    disk.conversation.select(DraftKey(hostId: config.pairing.hostId,
      workspaceId: config.workspaceId, sessionId: config.sessionId))
    try JSONEncoder().encode(disk).write(to: folder.appending(path: "drafts.json"),
      options: [.atomic, .completeFileProtection])
    return AppModel(pairingPersistence: PairingPersistence(load: { config.pairing },
      save: { _ in }, remove: {}), draftStore: isolatedStore)
  } catch {
    let isolated = AppModel(pairingPersistence: PairingPersistence(load: { nil }, save: { _ in }, remove: {}),
      draftStore: isolatedStore)
    isolated.notice = "The isolated question qualification could not be opened."
    return isolated
  }
}
#endif

// Isolated synthetic data only; native tests never load or change a real pairing.
@MainActor func chatUITestFixture(slowMessages: Bool, failRename: Bool, largeConversation: Bool = false,
  burstEvents: Bool = false, offlineReconnect: Bool = false, pendingQuestion: Bool = false,
  staleQuestion: Bool = false, unsupportedQuestion: Bool = false, slowQuestions: Bool = false) -> AppModel {
  let folder = FileManager.default.temporaryDirectory.appending(path: "chat-ui-" + UUID().uuidString)
  return AppModel(pairingPersistence: PairingPersistence(load: {
    StoredPairing(origin: "https://fixture.example.test", token: "synthetic", hostId: "fixture-host")
  }, save: { _ in }, remove: {}), transport: ChatUITestTransport(slowMessages: slowMessages, failRename: failRename,
    largeConversation: largeConversation, burstEvents: burstEvents, offlineReconnect: offlineReconnect,
    pendingQuestion: pendingQuestion, staleQuestion: staleQuestion, unsupportedQuestion: unsupportedQuestion, slowQuestions: slowQuestions),
    draftStore: try? DraftStore(directory: folder))
}
private actor ChatUITestTransport: HTTPTransport {
  let slowMessages: Bool
  let failRename: Bool
  let largeConversation: Bool
  let burstEvents: Bool
  let offlineReconnect: Bool
  let questionsEnabled: Bool
  let staleQuestion: Bool
  let unsupportedQuestion: Bool
  let slowQuestions: Bool
  var questionPending: Bool
  var connections = 0
  var title = "Sample chat"
  init(slowMessages: Bool, failRename: Bool, largeConversation: Bool, burstEvents: Bool, offlineReconnect: Bool,
    pendingQuestion: Bool, staleQuestion: Bool, unsupportedQuestion: Bool, slowQuestions: Bool) {
    self.slowMessages = slowMessages; self.failRename = failRename
    self.largeConversation = largeConversation; self.burstEvents = burstEvents; self.offlineReconnect = offlineReconnect
    self.questionsEnabled = pendingQuestion; self.questionPending = pendingQuestion
    self.staleQuestion = staleQuestion; self.unsupportedQuestion = unsupportedQuestion
    self.slowQuestions = slowQuestions
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
    if path.contains("/questions/frm_test/") {
      if staleQuestion { return (Data("{}".utf8), 409) }
      let body = try JSONDecoder().decode(QuestionSubmission.self, from: request.httpBody!)
      if path.hasSuffix("/reply"), body.answers != ["layout": .string("detailed"), "name": .string("Fixture project")] {
        return (Data("{}".utf8), 400)
      }
      questionPending = false
      return try response(["requestId": body.requestId, "resourceId": "frm_test", "state": "accepted", "observedAt": "now"])
    }
    if path.hasSuffix("/questions") {
      if slowQuestions { try await Task.sleep(for: .seconds(30)) }
      let fields: [[String: Any]] = [
        ["key": "layout", "kind": "singleChoice", "title": "Layout", "prompt": "Which approach would you prefer?", "custom": false,
         "options": [["value": "simple", "label": "Same label", "description": "Simple and focused"],
                     ["value": "detailed", "label": "Same label", "description": "More detail"]]],
        ["key": "name", "kind": "text", "title": "Project name", "prompt": "What should it be called?", "custom": true, "options": []],
      ]
      let question: [String: Any] = ["id": "frm_test", "sessionId": "ses_test", "revision": String(repeating: "a", count: 64),
        "supported": !unsupportedQuestion, "reason": unsupportedQuestion ? "Complete this request in OpenWork on your computer." : NSNull(),
        "fields": unsupportedQuestion ? [] : fields]
      return try response(questionPending ? [question] : [])
    }
    if path.hasSuffix("/rename") {
      if failRename { return (Data("{}".utf8), 503) }
      let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
      title = body["title"]!
      return try response(["requestId": body["requestId"]!, "resourceId": "ses_test", "state": "accepted", "observedAt": "now"])
    }
    if path.hasSuffix("/host") {
      return try response(["hostId": "fixture-host", "displayName": "Test computer", "platform": "linux", "architecture": "x64", "runtimeKind": "desktop", "protocolVersion": 1, "upstreamVersion": "0.18.57", "compatibility": "supported", "capabilities": ["readSessions": true, "readMessages": true, "readStatus": true, "events": true, "createSession": false, "sendText": false, "stop": false, "readApprovals": true, "replyApproval": false, "renameSession": true, "questions": questionsEnabled, "maxPromptBytes": 32768, "protocolVersion": 1]])
    }
    if path.hasSuffix("/workspaces") { return try response([["id": "ws_test", "name": "Test project"]]) }
    let session: [String: Any] = ["id": "ses_test", "workspaceId": "ws_test", "title": title, "updatedAt": "2026-10-08", "status": "idle"]
    if path.hasSuffix("/sessions") { return try response([session]) }
    if path.hasSuffix("/messages") {
      if slowMessages { try await Task.sleep(for: .seconds(30)) }
      if slowQuestions { return try response([["id": "msg_ready", "sessionId": "ses_test", "role": "assistant",
        "createdAt": "2026-10-08T12:00:00Z", "blocks": [["kind": "text", "text": "Chat is ready."]], "state": "complete"]]) }
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
