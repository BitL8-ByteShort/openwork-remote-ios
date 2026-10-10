import XCTest

@MainActor final class SkillUITests: XCTestCase {
  private let ownedID = "skill_" + String(repeating: "a", count: 64),
    managedID = "skill_" + String(repeating: "b", count: 64)
  private func open(_ flags: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats", "-skills"] + flags
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 15))
    app.buttons["Open chat history"].tap()
    let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat"))
      .firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
    chat.tap()
    openSkills(app)
    return app
  }
  private func openSkills(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["composer-add"].waitForExistence(timeout: 5))
    app.buttons["composer-add"].tap()
    app.buttons["Skills"].tap()
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
  func testManagedSkillStaysReadOnlyWhileWorkspaceSkillCanBeSelected() {
    let app = open()
    let managed = app.buttons["skill-row-" + managedID]
    XCTAssertTrue(managed.waitForExistence(timeout: 5))
    managed.tap()
    XCTAssertTrue(
      app.staticTexts[
        "These instructions stay on your computer. This skill can still be selected when OpenWork permits it."
      ].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["skill-edit"].isEnabled)
    XCTAssertFalse(app.buttons["skill-delete"].isEnabled)
    capture(app, "Managed skill remains read only")
    app.navigationBars.buttons["Skills"].tap()
    app.buttons["skill-row-" + ownedID].tap()
    XCTAssertTrue(app.staticTexts["skill-content"].waitForExistence(timeout: 5))
    app.buttons["skill-select"].tap()
    app.navigationBars.buttons["Skills"].tap()
    app.navigationBars["Skills"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["selected-skill-" + ownedID].waitForExistence(timeout: 3))
    let composer = app.textFields["composer"]
    composer.tap()
    composer.typeText("Keep this draft for approval")
    app.buttons["send-message"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(
          format: "label CONTAINS %@", "Review the selected skill permission on your computer")
      ).firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(composer.value as? String, "Keep this draft for approval")
    XCTAssertTrue(app.buttons["selected-skill-" + ownedID].exists)
    XCTAssertFalse(app.staticTexts["Delivery is uncertain"].exists)
  }
  func testStaleSaveKeepsTheEditedInstructions() {
    let app = open(["-stale-skills"])
    XCTAssertTrue(app.buttons["skill-row-" + ownedID].waitForExistence(timeout: 5))
    app.buttons["skill-row-" + ownedID].tap()
    app.buttons["skill-edit"].tap()
    let text = app.textViews["skill-editor-content"]
    XCTAssertTrue(text.waitForExistence(timeout: 5))
    text.tap()
    text.typeText(" Phone draft retained.")
    app.swipeUp()
    app.buttons["skill-save"].tap()
    XCTAssertTrue(app.staticTexts["skill-editor-notice"].waitForExistence(timeout: 5))
    XCTAssertTrue((text.value as? String)?.contains("Phone draft retained.") == true)
    XCTAssertFalse(app.buttons["skill-save"].isEnabled)
    capture(app, "Stale skill save keeps the phone draft")
    app.buttons["skill-editor-done"].tap()
    XCTAssertTrue(app.buttons["skill-edit"].waitForExistence(timeout: 3))
  }
  func testMissingGrantAndSlowCatalogDoNotBlockDone() {
    let denied = open(["-skills-denied"])
    XCTAssertTrue(denied.buttons["skill-row-" + ownedID].waitForExistence(timeout: 5))
    XCTAssertFalse(denied.buttons["skill-add"].isEnabled)
    denied.terminate()
    let slow = open(["-slow-skills"])
    slow.navigationBars["Skills"].buttons["Done"].tap()
    XCTAssertTrue(slow.buttons["composer-add"].waitForExistence(timeout: 3))
  }
}
