import XCTest

@MainActor final class LiveChatActionUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable { let origin: String, token: String }
    let pairing: Pairing
    let workspaceId: String, sessionId: String
  }
  func testPairedWholeForkAndLeafDeletePreserveTheOriginal() async throws {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else {
      throw XCTSkip("Needs an explicitly disposable attachment chat and temporary pairing.")
    }
    continueAfterFailure = false
    let config = try JSONDecoder().decode(
      Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let base = config.pairing.origin + "/v1/workspaces/" + config.workspaceId
    func get(_ suffix: String) async throws -> Any {
      var req = URLRequest(url: try XCTUnwrap(URL(string: base + suffix)))
      req.setValue("Bearer " + config.pairing.token, forHTTPHeaderField: "Authorization")
      let (d, r) = try await URLSession.shared.data(for: req)
      XCTAssertEqual((r as? HTTPURLResponse)?.statusCode, 200)
      return try XCTUnwrap((try JSONSerialization.jsonObject(with: d) as? [String: Any])?["data"])
    }
    func row(_ suffix: String) async throws -> [String: Any] {
      let v = try await get(suffix)
      return try XCTUnwrap(v as? [String: Any])
    }
    func rows(_ suffix: String) async throws -> [[String: Any]] {
      let v = try await get(suffix)
      return try XCTUnwrap(v as? [[String: Any]])
    }
    let parent = try await row("/sessions/" + config.sessionId)
    XCTAssertEqual(parent["title"] as? String, "Disposable remote attachments qualification")
    let originalMessages = try JSONSerialization.data(
      withJSONObject: try await get("/sessions/" + config.sessionId + "/messages"),
      options: .sortedKeys)
    let before = try await rows("/sessions")
    let oldIDs = Set(before.compactMap { $0["id"] as? String })
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-live-artifacts"]
    app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"] = path
    app.launch()
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout: 30))
    history.tap()
    let parentRow = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Disposable remote attachments qualification")
    ).firstMatch
    XCTAssertTrue(parentRow.waitForExistence(timeout: 10))
    parentRow.press(forDuration: 1)
    app.buttons["Continue in a new chat"].tap()
    let create = app.buttons["chat-action-confirm"]
    XCTAssertTrue(create.waitForExistence(timeout: 10))
    XCTAssertTrue(create.isEnabled)
    create.tap()
    XCTAssertTrue(history.waitForExistence(timeout: 15))
    let after = try await rows("/sessions")
    let new = after.filter { !oldIDs.contains($0["id"] as? String ?? "") }
    XCTAssertEqual(new.count, 1)
    let child = try XCTUnwrap(new.first)
    let sid = try XCTUnwrap(child["id"] as? String)
    let title = try XCTUnwrap(child["title"] as? String)
    XCTAssertNotEqual(sid, config.sessionId)
    let createdMessages = try await rows("/sessions/" + sid + "/messages")
    let parentMessages = try await rows("/sessions/" + config.sessionId + "/messages")
    XCTAssertEqual(createdMessages.count, parentMessages.count)
    history.tap()
    let childRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    XCTAssertTrue(childRow.waitForExistence(timeout: 10))
    childRow.press(forDuration: 1)
    app.buttons["Delete chat"].tap()
    let remove = app.buttons["chat-action-confirm"]
    XCTAssertTrue(remove.waitForExistence(timeout: 10))
    XCTAssertTrue(remove.isEnabled)
    remove.tap()
    XCTAssertTrue(app.buttons["groups-manage"].waitForExistence(timeout: 15))
    XCTAssertFalse(childRow.exists)
    XCTAssertTrue(parentRow.exists)
    let final = try await rows("/sessions")
    XCTAssertFalse(final.contains { $0["id"] as? String == sid })
    XCTAssertEqual(Set(final.compactMap { $0["id"] as? String }), oldIDs)
    let finalMessages = try JSONSerialization.data(
      withJSONObject: try await get("/sessions/" + config.sessionId + "/messages"),
      options: .sortedKeys)
    XCTAssertEqual(finalMessages, originalMessages)
  }
}
