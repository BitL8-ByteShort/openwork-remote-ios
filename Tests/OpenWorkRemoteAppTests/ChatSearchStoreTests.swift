import Foundation
import OpenWorkRemoteCore
import Testing

@testable import OpenWorkRemoteAppState

private actor TitleSearchTransport: HTTPTransport {
  var searches: [String] = [], delay = false, denied = false
  var continuation: CheckedContinuation<Void, Never>?
  func configure(delay: Bool = false, denied: Bool = false) {
    self.delay = delay
    self.denied = denied
  }
  func waiting() -> Bool { continuation != nil }
  func release() {
    continuation?.resume()
    continuation = nil
  }
  func queries() -> [String] { searches }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    if request.url!.path == "/v1/device/access" {
      return (
        try JSONSerialization.data(withJSONObject: [
          "data": [
            "allWorkspaces": false, "workspaceIds": denied ? [] : ["owned"],
            "features": [
              "fileTransfer": false, "workspaceAdministration": false,
              "automationManagement": false,
            ],
          ], "cursor": NSNull(),
        ]), 200
      )
    }
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    let query = items.first { $0.name == "q" }!.value!
    searches.append(query)
    if delay { await withCheckedContinuation { continuation = $0 } }
    let more = items.contains { $0.name == "cursor" }
    let rows: [[String: Any]] =
      query == "none"
      ? []
      : [
        [
          "id": "found", "workspaceId": "owned", "title": more ? "Renamed Homepage" : query,
          "updatedAt": "2026-10-09T00:00:00.000Z", "modelLabel": NSNull(), "status": "idle",
        ]
      ]
    let page: [String: Any] = [
      "data": rows, "cursor": more ? NSNull() : "00000000-0000-4000-8000-000000000001" as Any,
      "scanned": more ? 7 : 500, "complete": more,
    ]
    return (try JSONSerialization.data(withJSONObject: ["data": page, "cursor": NSNull()]), 200)
  }
}
@MainActor @Suite struct ChatSearchStoreTests {
  private func setup() -> (ChatSearchStore, ChatSearchContext, TitleSearchTransport, BridgeClient) {
    let s = ChatSearchStore()
    let c = ChatSearchContext(hostId: "fixture", workspaceId: "owned", generation: UUID())
    let t = TitleSearchTransport()
    s.activate(c)
    return (s, c, t, try! BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t))
  }
  private func settle(_ s: ChatSearchStore) async throws {
    for _ in 0..<300 {
      if !s.loading { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Search did not settle")
  }
  @Test func debounceKeepsOnlyLatestQueryAndEmptyClearMakesNoRequest() async throws {
    let (s, c, t, client) = setup()
    s.schedule("old", client: client, context: c, supported: true)
    s.schedule("home", client: client, context: c, supported: true)
    try await settle(s)
    #expect(await t.queries() == ["home"])
    #expect(s.results.first?.title == "home")
    s.schedule("", client: client, context: c, supported: true)
    #expect(s.results.isEmpty)
    #expect(!s.loading)
    #expect(await t.queries() == ["home"])
  }
  @Test func lateOldQueryAndOldWorkspaceNeverReplaceCurrentResults() async throws {
    let (s, c, t, client) = setup()
    await t.configure(delay: true)
    s.schedule("old", client: client, context: c, supported: true, debounce: false)
    for _ in 0..<100 {
      if await t.waiting() { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    await t.configure()
    s.schedule("new", client: client, context: c, supported: true, debounce: false)
    try await settle(s)
    await t.release()
    try await Task.sleep(for: .milliseconds(30))
    #expect(s.results.first?.title == "new")
    await t.configure(delay: true)
    s.schedule("late", client: client, context: c, supported: true, debounce: false)
    for _ in 0..<100 {
      if await t.waiting() { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    s.activate(nil)
    await t.release()
    try await Task.sleep(for: .milliseconds(30))
    #expect(s.results.isEmpty)
    #expect(s.context == nil)
  }
  @Test func incompleteEmptyResultsNeverClaimCompleteAndContinuationDeduplicatesRenamedIDs()
    async throws
  {
    let (s, c, _, client) = setup()
    s.schedule("none", client: client, context: c, supported: true, debounce: false)
    try await settle(s)
    #expect(s.results.isEmpty)
    #expect(!s.complete)
    #expect(s.cursor != nil)
    s.schedule("home", client: client, context: c, supported: true, debounce: false)
    try await settle(s)
    await s.more(client: client, context: c)
    #expect(s.results.count == 1)
    #expect(s.results.first?.title == "Renamed Homepage")
    #expect(s.complete)
    #expect(s.scanned == 507)
  }
  @Test func unsupportedAndRevokedProjectNeverSearchAndPreserveNoRemoteMetadata() async throws {
    let (s, c, t, client) = setup()
    s.schedule("home", client: client, context: c, supported: false, debounce: false)
    #expect(await t.queries().isEmpty)
    #expect(s.availability == .unsupported)
    await t.configure(denied: true)
    s.schedule("home", client: client, context: c, supported: true, debounce: false)
    try await settle(s)
    #expect(await t.queries().isEmpty)
    #expect(s.results.isEmpty)
    #expect(s.notice != nil)
  }
}
