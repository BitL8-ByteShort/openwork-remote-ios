import XCTest

/// Opt-in writes touch only the explicitly owned disposable group and chat.
/// The host qualification driver performs one native desktop rename and cleans
/// its temporary pairing; no prompts, model changes or full-state replacement.
@MainActor final class LiveGroupUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable {
      let origin: String
      let token: String
    }
    let pairing: Pairing
    let workspaceId: String
    let sessionId: String
  }
  func testPairedGroupEditsAndNativeDesktopRefreshPreserveTheChat() async throws {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else {
      throw XCTSkip("Needs an explicitly disposable project and temporary pairing.")
    }
    continueAfterFailure = false
    let config = try JSONDecoder().decode(
      Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let base = config.pairing.origin + "/v1/workspaces/" + config.workspaceId
    func read(_ suffix: String) async throws -> [String: Any] {
      var request = URLRequest(url: try XCTUnwrap(URL(string: base + suffix)))
      request.setValue("Bearer " + config.pairing.token, forHTTPHeaderField: "Authorization")
      let (data, response) = try await URLSession.shared.data(for: request)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
      return try XCTUnwrap(
        (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [String: Any])
    }
    let snapshot = try await read("/session-groups")
    let groups = try XCTUnwrap(snapshot["groups"] as? [[String: String]])
    XCTAssertEqual(groups.count, 1)
    let group = try XCTUnwrap(groups.first)
    XCTAssertEqual(group["label"], "Disposable live phone group")
    let id = try XCTUnwrap(group["id"])
    let owned = try await read("/sessions/" + config.sessionId)
    XCTAssertEqual(owned["title"] as? String, "Disposable workspace changes qualification")
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-live-artifacts"]
    app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"] = path
    app.launch()
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout: 30))
    history.tap()
    let manage = app.buttons["groups-manage"]
    XCTAssertTrue(manage.waitForExistence(timeout: 15))
    manage.tap()
    let edit = app.buttons["group-edit-" + id]
    XCTAssertTrue(edit.waitForExistence(timeout: 15))
    edit.tap()
    let field = app.textFields["group-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    // Put the cursor at the trailing edge, rather than the field's midpoint.
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Disposable live phone group".count)
        + "Disposable live phone rename")
    XCTAssertEqual(field.value as? String, "Disposable live phone rename")
    app.buttons["group-name-save"].tap()
    XCTAssertTrue(app.buttons["groups-manage-done"].waitForExistence(timeout: 15))
    app.buttons["groups-manage-done"].tap()
    let chat = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Disposable workspace changes qualification")
    ).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout: 10))
    chat.press(forDuration: 1)
    app.buttons["Move to group"].tap()
    XCTAssertTrue(app.buttons["move-group-" + id].waitForExistence(timeout: 5))
    app.buttons["move-group-" + id].tap()
    app.buttons["move-chat-save"].tap()
    let desktop = app.buttons["group-filter-" + id]
    XCTAssertTrue(desktop.waitForExistence(timeout: 15))
    let updated = NSPredicate(format: "label == %@", "Disposable live desktop rename")
    let desktopChange = expectation(for: updated, evaluatedWith: desktop)
    await fulfillment(of: [desktopChange], timeout: 20)
    let native = try await read("/session-groups")
    XCTAssertEqual((native["assignments"] as? [String: String])?[config.sessionId], id)
    manage.tap()
    let remove = app.buttons["group-remove-" + id]
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    remove.tap()
    app.alerts.buttons["Remove group"].tap()
    let removed = NSPredicate(format: "exists == false")
    let removal = expectation(for: removed, evaluatedWith: app.buttons["group-remove-" + id])
    await fulfillment(of: [removal], timeout: 15)
    app.buttons["groups-manage-done"].tap()
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
    let final = try await read("/session-groups")
    XCTAssertEqual((final["groups"] as? [[String: String]])?.count, 0)
    XCTAssertNil((final["assignments"] as? [String: String])?[config.sessionId])
    let finalChat = try await read("/sessions/" + config.sessionId)
    XCTAssertEqual(finalChat["title"] as? String, owned["title"] as? String)
    app.terminate()
  }
}
