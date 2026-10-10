import Foundation
import Testing

@testable import OpenWorkRemoteCore

@Test func unknownBlocksDoNotBlankTheConversation() throws {
  let json = Data(
    #"{"data":[{"id":"m1","sessionId":"s1","role":"assistant","createdAt":"2026-10-08T00:00:00Z","blocks":[{"kind":"future","script":"never execute"},{"kind":"text","text":"Safe reply"}],"state":"complete"}],"cursor":null}"#
      .utf8)
  let response = try JSONDecoder().decode(Envelope<[ChatMessage]>.self, from: json)
  #expect(response.data[0].blocks[0].kind == "unsupported")
  #expect(response.data[0].blocks[0].label == "Content available on computer")
  #expect(response.data[0].blocks[1].text == "Safe reply")
}
@Test func malformedPairingDoesNotProduceAnOrigin() throws {
  for data in [
    #"{"protocolVersion":1,"origin":"http://bad.test","pairingId":"6aaf91c4-f75b-4c4c-a18e-8914e58d9f05","secret":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#,
    "garbage",
  ] { #expect(throws: (any Error).self) { try PairingPayload.decode(data) } }
}
@Test func unknownBlockPayloadFieldsAreNotInterpreted() throws {
  let block = try JSONDecoder().decode(
    MessageBlock.self, from: Data(#"{"kind":"future","text":{"script":"run me"}}"#.utf8))
  #expect(block.kind == "unsupported")
  #expect(block.text == nil)
}
@Test func invalidPairingSecretIsRejectedBeforeConnecting() throws {
  let data =
    #"{"protocolVersion":1,"origin":"https://host.test","pairingId":"6aaf91c4-f75b-4c4c-a18e-8914e58d9f05","secret":"!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"}"#
  #expect(throws: (any Error).self) { try PairingPayload.decode(data) }
}
@Test func sharedBridgeFixturesDecodeInTheNativeClient() throws {
  let folder = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
  let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
  #expect(files.count > 10)
  for file in files {
    let wrapper = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    let data = try JSONSerialization.data(withJSONObject: wrapper["value"]!)
    let decoder = JSONDecoder()
    switch wrapper["type"] as! String {
    case "Host": _ = try decoder.decode(Host.self, from: data)
    case "WorkspaceList": _ = try decoder.decode([Workspace].self, from: data)
    case "SessionList": _ = try decoder.decode([ChatSession].self, from: data)
    case "MessageList":
      let messages = try decoder.decode([ChatMessage].self, from: data)
      #expect(messages.last?.state == "cancelled")
      #expect(messages.last?.blocks.map(\.kind) == ["text", "code", "tool", "omitted", "unsupported"])
    case "SessionStatus": _ = try decoder.decode(SessionStatus.self, from: data)
    case "ApprovalList": _ = try decoder.decode([Approval].self, from: data)
    case "Attachment": _ = try decoder.decode(OpenWorkRemoteCore.Attachment.self, from: data)
    case "AttachmentLimits": _ = try decoder.decode(AttachmentLimits.self, from: data)
    case "AttachmentMutation": _ = try decoder.decode(AttachmentMutation.self, from: data)
    case "ArtifactCatalog": _ = try decoder.decode(ArtifactCatalog.self, from: data)
    case "MutationReceipt": _ = try decoder.decode(MutationReceipt.self, from: data)
    case "PairClaim": _ = try decoder.decode(PairClaim.self, from: data)
    case "PairPoll": _ = try decoder.decode(PairPoll.self, from: data)
    case "EventHint": _ = try decoder.decode(EventHint.self, from: data)
    case "Error": break // HTTP error statuses are normalized by BridgeClient.
    default: Issue.record("Unrecognized shared fixture: \(file.lastPathComponent)")
    }
  }
}
