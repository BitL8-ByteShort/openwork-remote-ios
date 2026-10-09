import Foundation
import Testing

@testable import OpenWorkRemoteCore

private let revision = String(repeating: "a", count: 64)
private func snapshot(
  _ groups: [[String: String]] = [["id": "first", "label": "First"]],
  assignments: [String: String] = ["chat": "first"]
) throws -> Data {
  try JSONSerialization.data(withJSONObject: [
    "revision": revision, "groups": groups, "assignments": assignments,
  ])
}
private actor GroupTransport: HTTPTransport {
  var requests: [URLRequest] = []
  var status = 200
  func configure(_ status: Int) { self.status = status }
  func captured() -> [URLRequest] { requests }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    guard status == 200 else { throw RemoteError.unavailable }
    let value: Any
    if request.httpMethod == "GET" {
      value = try JSONSerialization.jsonObject(with: snapshot())
    } else {
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      let resource: Any
      if request.url!.path.hasSuffix("/reorder") {
        resource = NSNull()
      } else if request.url!.path.hasSuffix("/assignments/chat") {
        resource = "chat"
      } else if request.url!.path.hasSuffix("/first/rename")
        || request.url!.path.hasSuffix("/first/remove")
      {
        resource = "first"
      } else {
        resource =
          "grp_remote_" + (body["requestId"] as! String).replacingOccurrences(of: "-", with: "")
      }
      value = [
        "requestId": body["requestId"]!, "resourceId": resource, "state": "accepted",
        "observedAt": "2026-10-09T00:00:00.000Z",
      ]
    }
    return (try JSONSerialization.data(withJSONObject: ["data": value, "cursor": NSNull()]), 200)
  }
}
@Suite struct GroupTests {
  @Test func labelsUseNativeScalarAndUTF16LimitsWithoutTruncation() throws {
    #expect(try SessionGroup.label("  Work  ") == "Work")
    #expect(try SessionGroup.label(String(repeating: "😀", count: 60)).unicodeScalars.count == 60)
    for s in [
      "", String(repeating: "x", count: 101), String(repeating: "😀", count: 61), "A\nB",
      "A\u{202e}B",
    ] {
      #expect(throws: (any Error).self) { try SessionGroup.label(s) }
    }
  }
  @Test func snapshotIsClosedBoundedAndReferencesExistingGroups() throws {
    let good = try JSONDecoder().decode(GroupSnapshot.self, from: snapshot())
    #expect(good.groups.first?.id == "first")
    for data in [
      try snapshot([["id": "first", "label": "First"], ["id": "first", "label": "Again"]]),
      try snapshot(assignments: ["chat": "missing"]),
      try snapshot([["id": "../secret", "label": "Bad"]]),
      try snapshot(Array(repeating: ["id": "first", "label": "First"], count: 101)),
      Data(
        "{\"revision\":\"\(revision)\",\"groups\":[],\"assignments\":{},\"token\":\"unexpected\"}"
          .utf8),
    ] {
      #expect(throws: (any Error).self) { try JSONDecoder().decode(GroupSnapshot.self, from: data) }
    }
  }
  @Test func granularWritesUsePairedOriginRevisionAndStableUUID() async throws {
    let t = GroupTransport()
    let client = try BridgeClient(
      origin: URL(string: "https://fixture.test:9443")!, token: "synthetic", transport: t)
    let id = UUID()
    _ = try await client.sessionGroups("owned")
    for action in [
      GroupAction.create(label: "New"), .rename(id: "first", label: "Name"),
      .reorder(ids: ["first"]), .assign(sessionId: "chat", groupId: nil), .remove(id: "first"),
    ] {
      let r = try await client.changeGroup(
        "owned", action: action, revision: revision, requestId: id)
      #expect(r.requestId == id.uuidString.lowercased())
    }
    let requests = await t.captured()
    #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST", "POST", "POST", "POST"])
    #expect(requests[3].url?.path == "/v1/workspaces/owned/session-groups/reorder")
    #expect(requests[4].url?.path == "/v1/workspaces/owned/session-groups/assignments/chat")
    #expect(
      requests.allSatisfy {
        $0.url?.host == "fixture.test"
          && $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic"
      })
    for request in requests.dropFirst() {
      let body = try #require(
        try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
      #expect(body["requestId"] as? String == id.uuidString.lowercased())
      #expect(body["revision"] as? String == revision)
      #expect(body["state"] == nil)
    }
  }
  @Test func invalidReordersTargetsAndLostRepliesNeverAutoRetry() async throws {
    let t = GroupTransport()
    let client = try BridgeClient(origin: URL(string: "https://fixture.test")!, transport: t)
    for action in [
      GroupAction.reorder(ids: ["first", "first"]), .rename(id: "../foreign", label: "Name"),
      .assign(sessionId: "/foreign", groupId: "first"),
    ] {
      await #expect(throws: (any Error).self) {
        try await client.changeGroup("owned", action: action, revision: revision, requestId: UUID())
      }
    }
    #expect(await t.captured().isEmpty)
    await t.configure(503)
    await #expect(throws: RemoteError.unavailable) {
      try await client.changeGroup(
        "owned", action: .create(label: "New"), revision: revision, requestId: UUID())
    }
    #expect(await t.captured().count == 1)
  }
}
