#if DEBUG
  import Foundation
  import OpenWorkRemoteCore

  // Only synthetic, isolated data. This transport never loads a real pairing.
  actor SkillUITestTransport: HTTPTransport {
    let base: any HTTPTransport
    let ownedID = "skill_" + String(repeating: "a", count: 64),
      managedID = "skill_" + String(repeating: "b", count: 64)
    var revision = String(repeating: "c", count: 64),
      content =
        "---\nname: fixture-skill\ndescription: Synthetic workspace instructions.\n---\n\nOriginal fixture instructions.\n",
      removed = false
    let options = ProcessInfo.processInfo.arguments
    init(base: any HTTPTransport) { self.base = base }
    func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error> {
      try await base.events(for: request)
    }
    private func response(_ data: Any) throws -> (Data, Int) {
      (try JSONSerialization.data(withJSONObject: ["data": data]), 200)
    }
    private var owned: [String: Any] {
      [
        "id": ownedID, "name": "fixture-skill", "description": "Synthetic workspace instructions.",
        "source": "workspace", "editable": true, "selectable": true, "revision": revision,
      ]
    }
    private var managed: [String: Any] {
      [
        "id": managedID, "name": "managed-fixture", "description": "Synthetic managed entry.",
        "source": "managed", "editable": false, "selectable": true,
        "revision": String(repeating: "d", count: 64),
      ]
    }
    func data(for request: URLRequest) async throws -> (Data, Int) {
      let path = request.url!.path
      if path.contains("/skills") {
        if options.contains("-slow-skills") { try await Task.sleep(for: .seconds(30)) }
        if options.contains("-skills-unsupported") { return (Data(), 422) }
        if request.httpMethod == "POST" {
          let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
          if options.contains("-stale-skills") { return (Data(), 409) }
          if path.hasSuffix("/delete") {
            removed = true
          } else {
            content = body["content"] as! String
            revision = String(repeating: "e", count: 64)
          }
          var receipt: [String: Any] = [
            "requestId": body["requestId"]!, "resourceId": ownedID, "state": "accepted",
            "observedAt": "2026-10-09T00:00:00Z",
          ]
          if !removed { receipt["resourceRevision"] = revision }
          return try response(receipt)
        }
        if path.hasSuffix(ownedID) { return try response(["item": owned, "content": content]) }
        if path.hasSuffix(managedID) {
          return try response(["item": managed, "content": NSNull()])
        }
        return try response([
          "items": removed ? [managed] : [owned, managed],
          "revision": String(repeating: "f", count: 64),
        ])
      }
      if path.hasSuffix("/messages"), request.httpMethod == "POST" {
        return (Data("{\"error\":{\"code\":\"SKILL_APPROVAL_REQUIRED\"}}".utf8), 422)
      }
      let (data, status) = try await base.data(for: request)
      if path == "/v1/host" || path == "/v1/device/access" {
        var envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var value = envelope["data"] as! [String: Any]
        if path == "/v1/host" {
          var caps = value["capabilities"] as! [String: Any]
          caps["skillsRead"] = !options.contains("-skills-unsupported")
          caps["skillsWrite"] = !options.contains("-skills-unsupported")
          caps["skillsSelect"] = !options.contains("-skills-unsupported")
          caps["sendText"] = true
          value["capabilities"] = caps
        } else {
          var features = value["features"] as! [String: Any]
          features["workspaceAdministration"] = !options.contains("-skills-denied")
          value["features"] = features
        }
        envelope["data"] = value
        return (try JSONSerialization.data(withJSONObject: envelope), status)
      }
      return (data, status)
    }
  }
#endif
