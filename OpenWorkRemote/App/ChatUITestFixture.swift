#if DEBUG
import Foundation
import OpenWorkRemoteCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if targetEnvironment(simulator)
private struct LiveAttachmentConfiguration: Decodable {
  let pairing: StoredPairing
  let workspaceId: String
  let sessionId: String
  let fixtureDirectory: String
}
@MainActor func liveAttachmentUITestFixture() -> AppModel {
  let folder = FileManager.default.temporaryDirectory.appending(path:"live-attachments-" + UUID().uuidString)
  let isolatedStore: DraftStore
  do { isolatedStore = try DraftStore(directory:folder) }
  catch { preconditionFailure("The isolated attachment qualification store could not be created.") }
  do {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_ATTACHMENT_UI_CONFIG"] else { throw RemoteError.unavailable }
    let data = try Data(contentsOf:URL(fileURLWithPath:path)); guard data.count <= 65536 else { throw RemoteError.oversized }
    let config = try JSONDecoder().decode(LiveAttachmentConfiguration.self,from:data)
    _ = try PairingValidation.origin(config.pairing.origin)
    var disk = DiskState(); disk.conversation.select(DraftKey(hostId:config.pairing.hostId,workspaceId:config.workspaceId,sessionId:config.sessionId))
    try JSONEncoder().encode(disk).write(to:folder.appending(path:"drafts.json"),options:[.atomic,.completeFileProtection])
    return AppModel(pairingPersistence:PairingPersistence(load:{config.pairing},save:{ _ in },remove:{}),draftStore:isolatedStore)
  } catch {
    let model = AppModel(pairingPersistence:PairingPersistence(load:{nil},save:{ _ in },remove:{}),draftStore:isolatedStore)
    model.notice = "The isolated attachment qualification could not be opened."; return model
  }
}
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
  let isolatedStore: DraftStore
  do { isolatedStore = try DraftStore(directory:folder) }
  catch { preconditionFailure("The isolated chat qualification store could not be created.") }
  return AppModel(pairingPersistence: PairingPersistence(load: {
    StoredPairing(origin: "https://fixture.example.test", token: "synthetic", hostId: "fixture-host")
  }, save: { _ in }, remove: {}), transport: ChatUITestTransport(slowMessages: slowMessages, failRename: failRename,
    largeConversation: largeConversation, burstEvents: burstEvents, offlineReconnect: offlineReconnect,
    pendingQuestion: pendingQuestion, staleQuestion: staleQuestion, unsupportedQuestion: unsupportedQuestion, slowQuestions: slowQuestions),
    draftStore: isolatedStore)
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
  let attachmentsEnabled = ProcessInfo.processInfo.arguments.contains("-attachments")
  let fileAccessDenied = ProcessInfo.processInfo.arguments.contains("-attachment-denied")
  let loseAttachmentCommit = ProcessInfo.processInfo.arguments.contains("-attachment-lost-commit")
  var attachmentFiles: [String: [String: Any]] = [:]
  var allocations: [String: String] = [:]
  var attachmentPromptAccepted = false
  var attachmentPromptCount = 0
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
    if path.contains("/attachments") {
      if path.hasSuffix("/limits") { return try response(["maxFileBytes":20_971_520,"inputMIMEs":["image/png","application/pdf"]]) }
      let body = request.value(forHTTPHeaderField:"Content-Type") == "application/octet-stream" ? [:]
        : try request.httpBody.map { try JSONSerialization.jsonObject(with:$0) as! [String:Any] } ?? [:]
      let uuid = body["requestId"] as? String ?? ""
      var id: String
      if path.hasSuffix("/attachments") {
        id = allocations[uuid] ?? "att_" + String(format:"%032x",attachmentFiles.count + 1)
        if allocations[uuid] == nil {
          allocations[uuid] = id
          attachmentFiles[id] = ["id":id,"name":body["name"]!,"mime":body["mime"]!,"bytes":body["bytes"]!,
            "sha256":body["sha256"]!,"receivedBytes":0,"state":"uploading"]
        }
      } else {
        id = path.components(separatedBy:"/attachments/").last!.components(separatedBy:"/").first!
      }
      guard var file = attachmentFiles[id] else { return (Data("{}".utf8),404) }
      if path.hasSuffix("/chunks") {
        let offset = Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first!.value!)!
        file["receivedBytes"] = offset + request.httpBody!.count
      }
      if path.hasSuffix("/commit") { file["state"] = "ready" }
      if path.hasSuffix("/cancel") { file["state"] = "cancelled" }
      attachmentFiles[id] = file
      if path.hasSuffix("/commit"), loseAttachmentCommit { throw RemoteError.outcomeUnknown }
      if request.httpMethod == "POST" {
        return try response(["receipt":["requestId":uuid,"resourceId":id,"state":"accepted","observedAt":"now"],"attachment":file])
      }
      return try response(file)
    }
    if path.hasSuffix("/messages"), request.httpMethod == "POST" {
      let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      let ids = body["attachmentIds"] as? [String] ?? []
      guard ids.count == 2, Set(ids).count == 2,
        ids.allSatisfy({ attachmentFiles[$0]?["state"] as? String == "ready" }), attachmentPromptCount == 0 else { return (Data("{}".utf8),409) }
      attachmentPromptCount += 1; attachmentPromptAccepted = true
      for id in ids { attachmentFiles[id]?["state"] = "attached" }
      return try response(["requestId":body["requestId"]!,"resourceId":"ses_test","state":"accepted","observedAt":"now"])
    }
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
      return try response(["hostId": "fixture-host", "displayName": "Test computer", "platform": "linux", "architecture": "x64", "runtimeKind": "desktop", "protocolVersion": 1, "upstreamVersion": "0.18.57", "compatibility": "supported", "capabilities": ["readSessions": true, "readMessages": true, "readStatus": true, "events": true, "createSession": false, "sendText": attachmentsEnabled, "stop": false, "readApprovals": true, "replyApproval": false, "renameSession": true, "questions": questionsEnabled, "attachments":attachmentsEnabled,"maxPromptBytes": 32768, "protocolVersion": 1]])
    }
    if path.hasSuffix("/workspaces") { return try response([["id": "ws_test", "name": "Test project"]]) }
    let session: [String: Any] = ["id": "ses_test", "workspaceId": "ws_test", "title": title, "updatedAt": "2026-10-08", "status": "idle"]
    if path.hasSuffix("/sessions") { return try response([session]) }
    if path.hasSuffix("/messages") {
      if attachmentPromptAccepted { return try response([["id":"msg_attachment_fixture","sessionId":"ses_test","role":"assistant",
        "createdAt":"2026-10-09T12:00:00Z","blocks":[["kind":"text","text":"Fixture attachment prompt accepted once."]],"state":"complete"]]) }
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
        "features": ["fileTransfer": !fileAccessDenied, "workspaceAdministration": false, "automationManagement": false]])
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

private actor AttachmentUITestSamples {
  static let shared = AttachmentUITestSamples()
  func selected(photo: Bool) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path:"attachment-ui-selected-" + UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,
      attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.complete])
    let url = root.appending(path:photo ? "fixture.png" : "fixture.pdf")
    if photo {
      let context = CGContext(data:nil,width:4,height:4,bitsPerComponent:8,bytesPerRow:16,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.setFillColor(CGColor(red:0,green:1,blue:0,alpha:1)); context.fill(CGRect(x:0,y:0,width:4,height:4))
      let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
      CGImageDestinationAddImage(destination,context.makeImage()!,nil)
      guard CGImageDestinationFinalize(destination) else { throw RemoteError.invalidResponse }
    } else { try Data("%PDF-1.7\nSynthetic selected document\n%%EOF\n".utf8).write(to:url,options:.completeFileProtection) }
    return url
  }
}
@MainActor func addAttachmentUITestSample(model: AppModel, context: AttachmentContext, photo: Bool) async {
  do {
    #if targetEnvironment(simulator)
    if ProcessInfo.processInfo.arguments.contains("-ui-testing-live-attachments") {
      guard let path = ProcessInfo.processInfo.environment["OPENWORK_ATTACHMENT_UI_CONFIG"] else { throw RemoteError.unavailable }
      let config = try JSONDecoder().decode(LiveAttachmentConfiguration.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
      guard context.key.hostId == config.pairing.hostId, context.key.workspaceId == config.workspaceId,
        context.key.sessionId == config.sessionId else { throw RemoteError.unavailable }
      let selected = URL(fileURLWithPath:config.fixtureDirectory,isDirectory:true).appending(path:photo ? "photo.png" : "document.pdf")
      let file = try await photo ? model.attachments.files.importPhoto(selected) : model.attachments.files.importPDF(selected)
      await model.addAttachment(file,context:context); return
    }
    #endif
    let selected = try await AttachmentUITestSamples.shared.selected(photo:photo)
    defer { try? FileManager.default.removeItem(at:selected.deletingLastPathComponent()) }
    let file = try await photo ? model.attachments.files.importPhoto(selected) : model.attachments.files.importPDF(selected)
    await model.addAttachment(file,context:context)
  } catch { model.notice = "The isolated attachment fixture could not be opened." }
}
#endif
