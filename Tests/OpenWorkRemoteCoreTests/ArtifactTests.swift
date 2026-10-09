import Foundation
import Testing
@testable import OpenWorkRemoteCore

private let resultID = "art_" + String(repeating: "a", count: 32)
private let revision = String(repeating: "b", count: 64)
private let artifactJSON = #"{"id":"art_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sessionId":"ses_test","name":"report.txt","mime":"text/plain","bytes":17,"revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","previewKind":"text"}"#
private actor ArtifactTransport: HTTPTransport {
  var requests: [URLRequest] = []
  var fault = ""
  func configure(_ fault: String) { self.fault = fault }
  func captured() -> [URLRequest] { requests }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    return (Data("{\"data\":{\"items\":[\(artifactJSON)],\"moreOnComputer\":false},\"cursor\":null}".utf8), 200)
  }
  func binary(for request: URLRequest, maximumBytes: Int) async throws -> BinaryHTTPResponse {
    requests.append(request)
    if fault == "lost" { throw RemoteError.unavailable }
    return BinaryHTTPResponse(data: fault == "long" ? Data(repeating: 0, count: 18) : Data("generated result\n".utf8),
      status: fault == "unauthorized" ? 401 : 206, mime: fault == "mime" ? "text/html" : "text/plain",
      contentRange: fault == "range" ? "bytes 0-16/18" : "bytes 0-16/17", entityTag: fault == "revision" ? "\"different\"" : "\"\(revision)\"", length: 17)
  }
}
@Suite struct ArtifactTests {
  @Test func resultReferencesAreClosedScopedBoundedAndCannotDescribeActivePreviews() throws {
    let valid = try JSONDecoder().decode(ArtifactRef.self, from: Data(artifactJSON.utf8))
    #expect(valid.name == "report.txt")
    for json in [artifactJSON.dropLast() + ",\"path\":\"/private/secret\"}",
      artifactJSON.replacingOccurrences(of: "report.txt", with: "../report.txt"),
      artifactJSON.replacingOccurrences(of: "\"bytes\":17", with: "\"bytes\":20971521"),
      artifactJSON.replacingOccurrences(of: "text/plain", with: "text/html"),
      artifactJSON.replacingOccurrences(of: "\"previewKind\":\"text\"", with: "\"previewKind\":\"image\""),
      artifactJSON.replacingOccurrences(of: "report.txt", with: "payload.svg")] {
      #expect(throws: (any Error).self) { try JSONDecoder().decode(ArtifactRef.self, from: Data(json.utf8)) }
    }
  }
  @Test func catalogRejectsDuplicateHandlesAndForeignSessions() async throws {
    let duplicate = "{\"items\":[\(artifactJSON),\(artifactJSON)],\"moreOnComputer\":false}"
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ArtifactCatalog.self, from: Data(duplicate.utf8)) }
    let transport = ArtifactTransport(), client = try BridgeClient(origin: URL(string: "https://fixture.test:9443")!, token: "synthetic", transport: transport)
    #expect(try await client.artifacts("ws_test", "ses_test").items.count == 1)
    await #expect(throws: RemoteError.invalidResponse) { try await client.artifacts("ws_test", "ses_foreign") }
  }
  @Test func rangeReadsStayOnThePairedOriginAndVerifyTypeRevisionRangeAndLength() async throws {
    let transport = ArtifactTransport(), client = try BridgeClient(origin: URL(string: "https://fixture.test:9443")!, token: "synthetic", transport: transport)
    let ref = try JSONDecoder().decode(ArtifactRef.self, from: Data(artifactJSON.utf8))
    #expect(try await client.artifactChunk("ws_test", "ses_test", ref: ref, offset: 0) == Data("generated result\n".utf8))
    let request = try #require(await transport.captured().first)
    #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-16")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
    #expect(request.url?.absoluteString == "https://fixture.test:9443/v1/workspaces/ws_test/sessions/ses_test/artifacts/\(resultID)/content?revision=\(revision)")
    for fault in ["long", "mime", "range", "revision"] {
      await transport.configure(fault)
      await #expect(throws: RemoteError.invalidResponse) { try await client.artifactChunk("ws_test", "ses_test", ref: ref, offset: 0) }
    }
    await transport.configure("unauthorized")
    await #expect(throws: RemoteError.unauthorized) { try await client.artifactChunk("ws_test", "ses_test", ref: ref, offset: 0) }
  }
  @Test func invalidOffsetsForeignReferencesAndUncertainReadsNeverTriggerAutomaticNetworkRetries() async throws {
    let transport = ArtifactTransport(), client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: transport)
    let ref = try JSONDecoder().decode(ArtifactRef.self, from: Data(artifactJSON.utf8))
    for offset in [-1, 1, 17] { await #expect(throws: RemoteError.invalidResponse) { try await client.artifactChunk("ws_test", "ses_test", ref: ref, offset: offset) } }
    await #expect(throws: RemoteError.invalidResponse) { try await client.artifactChunk("ws_test", "other", ref: ref, offset: 0) }
    #expect(await transport.captured().isEmpty)
    await transport.configure("lost")
    await #expect(throws: RemoteError.unavailable) { try await client.artifactChunk("ws_test", "ses_test", ref: ref, offset: 0) }
    #expect(await transport.captured().count == 1)
  }
}
