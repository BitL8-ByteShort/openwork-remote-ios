import XCTest

final class ChatTests: XCTestCase {
  @MainActor private func chats(_ options: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats"] + options
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 5))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["Sample chat"].waitForExistence(timeout: 5))
    return app
  }
  @MainActor func testOpeningChatDoesNotWaitForMessages() {
    let app = chats(["-slow-messages"])
    app.buttons["Sample chat"].tap()
    let header = app.buttons["Open chat history"]
    let responsive = NSPredicate(format: "isHittable == true")
    expectation(for: responsive, evaluatedWith: header)
    waitForExpectations(timeout: 3)
    // The 30-second network read is still pending; navigation remains available.
    header.tap()
    XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
    app.buttons["Done"].tap()
    XCTAssertTrue(header.isHittable)
  }
  @MainActor func testLongPressRenameSavesAndCancelKeepsOriginal() {
    let app = chats()
    app.buttons["Sample chat"].press(forDuration: 0.8)
    app.buttons["Rename"].tap()
    let field = app.textFields["chat-name"].exists ? app.textFields["chat-name"] : app.textViews["chat-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    XCTAssertEqual(field.value as? String, "Sample chat")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["Sample chat"].exists)
    app.buttons["Sample chat"].press(forDuration: 0.8)
    app.buttons["Rename"].tap()
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 11) + "Renamed on phone")
    app.buttons["save-chat-name"].tap()
    XCTAssertTrue(app.buttons["Renamed on phone"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Sample chat"].exists)
  }
  @MainActor func testFailedRenameKeepsEnteredTitle() {
    let app = chats(["-fail-rename"])
    app.buttons["Sample chat"].press(forDuration: 0.8)
    app.buttons["Rename"].tap()
    let field = app.textFields["chat-name"].exists ? app.textFields["chat-name"] : app.textViews["chat-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 11) + "Keep my edit")
    app.buttons["save-chat-name"].tap()
    XCTAssertTrue(app.staticTexts["rename-error"].waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "Keep my edit")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["Sample chat"].exists)
  }
}
