import Foundation
import Testing

@testable import OpenWorkRemoteCore

actor RecordingTransport: HTTPTransport {
  var requests: [URLRequest] = []
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    return (Data(#"{"data":[{"id":"ws_one","name":"Work"}],"cursor":null}"#.utf8), 200)
  }
  func recorded() -> [URLRequest] { requests }
}
@Test func authenticatedRequestsStayOnThePairedOrigin() async throws {
  let transport = RecordingTransport()
  let client = try BridgeClient(
    origin: URL(string: "https://paired.test:9443")!, token: "device-only", transport: transport)
  let workspaces = try await client.workspaces()
  #expect(workspaces.data.map(\.id) == ["ws_one"])
  let request = await transport.recorded().first!
  #expect(request.url?.absoluteString == "https://paired.test:9443/v1/workspaces")
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-only")
}
