import XCTest

@MainActor final class LiveSkillUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable { let origin: String, token: String }
    let pairing: Pairing, workspaceId: String, sessionId: String, skillId: String, skillName: String
  }
  func testPairedSkillEditSelectionAndExplicitRemoval() async throws {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else {
      throw XCTSkip("Requires a temporary paired disposable text skill")
    }
    continueAfterFailure = false
    let config = try JSONDecoder().decode(
      Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-live-artifacts"]
    app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"] = path
    app.launch()
    XCTAssertTrue(app.buttons["composer-add"].waitForExistence(timeout: 30))
    app.buttons["composer-add"].tap()
    app.buttons["Skills"].tap()
    let row = app.buttons["skill-row-" + config.skillId]
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "skill-row-")).firstMatch
        .waitForExistence(timeout: 30))
    XCTAssertTrue(reveal(row, in: app))
    row.tap()
    let edit = app.buttons["skill-edit"]
    XCTAssertTrue(edit.waitForExistence(timeout: 20))
    XCTAssertTrue(edit.isEnabled)
    edit.tap()
    let editor = app.textViews["skill-editor-content"]
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    editor.tap()
    editor.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.98)).tap()
    editor.typeText("\nPaired native phone edit verified.\n")
    app.swipeUp()
    app.buttons["skill-save"].tap()
    let closed = expectation(for: NSPredicate(format: "exists == NO"), evaluatedWith: editor)
    await fulfillment(of: [closed], timeout: 30)
    app.swipeDown()
    let content = app.staticTexts["skill-content"]
    let updated = expectation(
      for: NSPredicate(format: "label CONTAINS %@", "Paired native phone edit verified."),
      evaluatedWith: content)
    await fulfillment(of: [updated], timeout: 30)
    app.buttons["skill-select"].tap()
    app.navigationBars.buttons["Skills"].tap()
    app.navigationBars["Skills"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["selected-skill-" + config.skillId].waitForExistence(timeout: 5))
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Paired workspace skill selected for the next message"
    capture.lifetime = .keepAlways
    add(capture)
    app.buttons["composer-add"].tap()
    app.buttons["Skills"].tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "skill-row-")).firstMatch
        .waitForExistence(timeout: 20))
    XCTAssertTrue(reveal(row, in: app))
    row.tap()
    let remove = app.buttons["skill-delete"]
    XCTAssertTrue(remove.waitForExistence(timeout: 15))
    remove.tap()
    app.buttons["Remove skill"].tap()
    XCTAssertTrue(reveal(app.buttons["skill-add"], in: app))
    XCTAssertFalse(row.exists)
    var request = URLRequest(
      url: URL(string: config.pairing.origin + "/v1/workspaces/" + config.workspaceId + "/skills")!)
    request.setValue("Bearer " + config.pairing.token, forHTTPHeaderField: "Authorization")
    let (bytes, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let catalog = try XCTUnwrap(envelope["data"] as? [String: Any])
    let items = try XCTUnwrap(catalog["items"] as? [[String: Any]])
    XCTAssertFalse(items.contains { $0["id"] as? String == config.skillId })
  }

  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    for _ in 0..<20 {
      if element.exists && element.isHittable { return true }
      app.swipeUp()
    }
    return element.exists && element.isHittable
  }
}
