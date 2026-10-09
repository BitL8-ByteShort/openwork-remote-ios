import Foundation
import Testing
@testable import OpenWorkRemoteCore

private let fileID = "att_" + String(repeating: "a", count: 32)
private let fileHash = String(repeating: "b", count: 64)
private let attachmentJSON = #"{"id":"att_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":"photo.png","mime":"image/png","bytes":68,"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","receivedBytes":68,"state":"ready"}"#
private actor FileTransport: HTTPTransport {
  var requests: [URLRequest] = []
  var lost = false
  var changedID = false
  func configure(lost: Bool = false, changedID: Bool = false) { self.lost = lost; self.changedID = changedID }
  func captured() -> [URLRequest] { requests }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    if lost { throw RemoteError.unavailable }
    let path = request.url!.path
    let value: String
    if path.hasSuffix("/limits") { value = #"{"maxFileBytes":20971520,"inputMIMEs":["image/png","application/pdf"]}"# }
    else if request.httpMethod == "PUT" || request.httpMethod == "GET" { value = changedID ? attachmentJSON.replacingOccurrences(of: "att_aaaaaaaa", with: "att_cccccccc") : attachmentJSON }
    else {
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      let uuid = body["requestId"] as! String
      let resource = path.hasSuffix("/messages") ? "ses_test" : fileID
      let receipt = "{\"requestId\":\"\(uuid)\",\"resourceId\":\"\(resource)\",\"state\":\"accepted\",\"observedAt\":\"2026-10-09T00:00:00Z\"}"
      value = path.hasSuffix("/messages") ? receipt : "{\"receipt\":\(receipt),\"attachment\":\(attachmentJSON)}"
    }
    return (Data("{\"data\":\(value),\"cursor\":null}".utf8), 200)
  }
}
@Suite struct AttachmentTests {
  private func client(_ transport: FileTransport) throws -> BridgeClient {
    try BridgeClient(origin: URL(string: "https://fixture.example.test:9443")!, token: "synthetic", transport: transport)
  }
  @Test func boundedMetadataAndUnknownFieldsAreChecked() throws {
    let file = try JSONDecoder().decode(OpenWorkRemoteCore.Attachment.self, from: Data(attachmentJSON.utf8))
    try file.validate()
    #expect(file.state == .ready)
    for json in [attachmentJSON.replacingOccurrences(of: "\"bytes\":68", with: "\"bytes\":20971521"),
      attachmentJSON.replacingOccurrences(of: "\"receivedBytes\":68", with: "\"receivedBytes\":69"),
      attachmentJSON.replacingOccurrences(of: "\"photo.png\"", with: "\"../photo.png\""),
      attachmentJSON.dropLast() + ",\"uri\":\"file:///private/hidden\"}"] {
      #expect(throws: (any Error).self) { try JSONDecoder().decode(OpenWorkRemoteCore.Attachment.self, from: Data(json.utf8)).validate() }
    }
  }
  @Test func chunkUsesBinaryBodyAndPreservesOriginAndCredential() async throws {
    let transport = FileTransport(), client = try client(transport)
    let bytes = Data(repeating: 7, count: 1_048_576)
    _ = try await client.putAttachmentChunk("ws_test", "ses_test", id: fileID, offset: 0, bytes: bytes)
    let request = try #require(await transport.captured().first)
    #expect(request.httpBody == bytes)
    #expect(request.httpMethod == "PUT")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
    #expect(request.url?.absoluteString == "https://fixture.example.test:9443/v1/workspaces/ws_test/sessions/ses_test/attachments/\(fileID)/chunks?offset=0")
    await #expect(throws: RemoteError.oversized) { try await client.putAttachmentChunk("ws_test", "ses_test", id: fileID, offset: 0, bytes: Data(repeating: 0, count: 1_048_577)) }
    #expect(await transport.captured().count == 1)
  }
  @Test func invalidMetadataAndForeignIDsNeverProduceAUsableDraft() async throws {
    let transport = FileTransport(), client = try client(transport)
    await #expect(throws: RemoteError.invalidResponse) {
      try await client.beginAttachment("ws_test", "ses_test", name: "../file.pdf", mime: "application/pdf", bytes: 10, sha256: fileHash, requestId: UUID())
    }
    #expect(await transport.captured().isEmpty)
    await transport.configure(changedID: true)
    await #expect(throws: RemoteError.invalidResponse) { try await client.attachment("ws_test", "ses_test", id: fileID) }
  }
  @Test func promptSendsOnlyOpaqueIDsAndDoesNotRepeatALostResponse() async throws {
    let transport = FileTransport(), client = try client(transport), uuid = UUID()
    let receipt = try await client.sendAttachments("ws_test", "ses_test", text: "", attachmentIds: [fileID], requestId: uuid)
    #expect(receipt.requestId == uuid.uuidString.lowercased())
    let request = try #require(await transport.captured().first)
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    #expect(Set(body.keys) == ["requestId", "text", "attachmentIds"])
    #expect(body["attachmentIds"] as? [String] == [fileID])
    await transport.configure(lost: true)
    await #expect(throws: RemoteError.unavailable) { try await client.sendAttachments("ws_test", "ses_test", text: "", attachmentIds: [fileID], requestId: UUID()) }
    #expect(await transport.captured().count == 2)
    await #expect(throws: RemoteError.invalidResponse) { try await client.sendAttachments("ws_test", "ses_test", text: "", attachmentIds: [fileID, fileID], requestId: UUID()) }
    #expect(await transport.captured().count == 2)
  }
  @Test func effectiveLimitsExcludeUnqualifiedMIME() async throws {
    let limits = try await client(FileTransport()).attachmentLimits("ws_test", "ses_test")
    #expect(limits.maxFileBytes == 20 * 1_048_576)
    #expect(limits.inputMIMEs == ["image/png", "application/pdf"])
  }
}
