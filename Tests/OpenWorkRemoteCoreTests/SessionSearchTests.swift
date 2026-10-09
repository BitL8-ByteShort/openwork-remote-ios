import Foundation
import Testing

@testable import OpenWorkRemoteCore

private actor SearchRequestTransport: HTTPTransport {
  var requests: [URLRequest] = []
  func captured() -> [URLRequest] { requests }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    return (
      Data(#"{"data":{"data":[],"cursor":null,"scanned":0,"complete":true},"cursor":null}"#.utf8),
      200
    )
  }
}
@Suite struct SessionSearchTests {
  @Test func fixedScopedGETEncodesQueryAndOpaqueCursorWithoutAProxy() async throws {
    let t = SearchRequestTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test:9443")!, transport: t)
    let cursor = UUID().uuidString.lowercased()
    _ = try await client.searchSessions("owned", query: "Home & café", cursor: cursor)
    let r = try #require(await t.captured().first)
    let u = try #require(URLComponents(url: r.url!, resolvingAgainstBaseURL: false))
    #expect(r.httpMethod == "GET")
    #expect(u.path == "/v1/workspaces/owned/sessions/search")
    #expect(
      u.queryItems == [
        URLQueryItem(name: "q", value: "Home & café"), URLQueryItem(name: "cursor", value: cursor),
      ])
    for query in ["", " ", String(repeating: "x", count: 201), "a\u{0}b"] {
      await #expect(throws: (any Error).self) {
        _ = try await client.searchSessions("owned", query: query)
      }
    }
    await #expect(throws: (any Error).self) {
      _ = try await client.searchSessions("../foreign", query: "home")
    }
    await #expect(throws: (any Error).self) {
      _ = try await client.searchSessions("owned", query: "home", cursor: "native-secret")
    }
    #expect(await t.captured().count == 1)
  }
  @Test func pageRejectsExtrasBoundsAndContradictoryCompletion() throws {
    let base: [String: Any] = ["data": [], "cursor": NSNull(), "scanned": 0, "complete": true]
    _ = try JSONDecoder().decode(
      SessionSearchPage.self, from: JSONSerialization.data(withJSONObject: base))
    for change in [
      ["path": "/foreign"], ["scanned": 501], ["scanned": -1], ["complete": false],
      ["cursor": "secret"], ["cursor": UUID().uuidString.lowercased()],
    ] as [[String: Any]] {
      #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(
          SessionSearchPage.self,
          from: JSONSerialization.data(withJSONObject: base.merging(change) { _, new in new }))
      }
    }
  }
}
