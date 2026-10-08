import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor RenameTransport: HTTPTransport {
  var requests: [URLRequest] = []
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    return (Data(#"{"data":{"requestId":"00000000-0000-4000-8000-000000000000","resourceId":"ses_test","state":"accepted","observedAt":"now"}}"#.utf8), 200)
  }
}
@Test func renameUsesScopedRouteAndStableRequestID() async throws {
  let transport = RenameTransport()
  let client = try BridgeClient(origin: URL(string: "https://paired.test:9443")!, token: "synthetic", transport: transport)
  let id = UUID()
  for _ in 0..<2 {
    _ = try await client.rename("ws_test", "ses_test", title: "  A new title  ", previousTitle: "Old title", requestId: id)
  }
  let requests = await transport.requests
  #expect(requests.count == 2)
  #expect(requests[0].url?.absoluteString == "https://paired.test:9443/v1/workspaces/ws_test/sessions/ses_test/rename")
  #expect(requests[0].httpMethod == "POST")
  let body = try #require(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
  let replay = try #require(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: String])
  #expect(body == replay)
  #expect(body == ["requestId": id.uuidString.lowercased(), "title": "A new title", "previousTitle": "Old title"])
}
@Test func renameRejectsEmptyAndOversizedTitlesBeforeNetworking() async throws {
  let transport = RenameTransport()
  let client = try BridgeClient(origin: URL(string: "https://paired.test")!, transport: transport)
  for title in [" \n ", String(repeating: "a", count: 201)] {
    await #expect(throws: RemoteError.self) {
      try await client.rename("ws_test", "ses_test", title: title, previousTitle: "Old", requestId: UUID())
    }
  }
  #expect(await transport.requests.isEmpty)
}
