import XCTest

final class QuestionUITests: XCTestCase {
  @MainActor private func selectedChat(_ arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats", "-pending-question"] + arguments
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 5))
    app.buttons["Open chat history"].tap()
    let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout: 5)); chat.tap()
    return app
  }
  @MainActor private func open(_ arguments: [String] = []) -> XCUIApplication {
    let app = selectedChat(arguments)
    let banner = app.buttons["question-banner"]
    XCTAssertTrue(banner.waitForExistence(timeout: 5)); banner.tap()
    return app
  }
  @MainActor func testSlowQuestionsDoNotHideLoadedMessages() {
    let app = selectedChat(["-slow-questions"])
    XCTAssertTrue(app.staticTexts["Chat is ready."].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["question-banner"].exists)
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
  }
  @MainActor func testChoicesAndTextStayDraftsUntilExplicitSend() {
    let app = open()
    let next = app.buttons["question-next"]
    XCTAssertTrue(next.waitForExistence(timeout: 5)); XCTAssertFalse(next.isEnabled)
    app.buttons["question-option-detailed"].tap()
    let choices = XCTAttachment(screenshot: app.screenshot())
    choices.name = "Question choice - neutral wording"; choices.lifetime = .keepAlways; add(choices)
    next.tap()
    let text = app.textFields["question-text-name"]
    XCTAssertTrue(text.waitForExistence(timeout: 3)); text.tap(); text.typeText("Fixture project")
    app.buttons["Cancel"].tap()
    app.buttons["question-banner"].tap()
    app.buttons["question-next"].tap()
    XCTAssertEqual(app.textFields["question-text-name"].value as? String, "Fixture project")
    app.buttons["question-send"].tap()
    XCTAssertTrue(app.staticTexts["Answers sent."].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Question answers sent"; screenshot.lifetime = .keepAlways; add(screenshot)
  }
  @MainActor func testStaleQuestionRetainsTextAndBlocksResending() {
    let app = open(["-stale-question"])
    app.buttons["question-option-detailed"].tap()
    app.buttons["question-next"].tap()
    let text = app.textFields["question-text-name"]
    text.tap(); text.typeText("Retained draft")
    app.buttons["question-send"].tap()
    XCTAssertTrue(app.staticTexts["question-notice"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["question-notice"].label.contains("changed"))
    XCTAssertEqual(text.value as? String, "Retained draft")
    XCTAssertFalse(app.buttons["question-send"].isEnabled)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Question changed - draft retained"; screenshot.lifetime = .keepAlways; add(screenshot)
  }
  @MainActor func testUnsupportedQuestionHandsOffWithoutSend() {
    let app = open(["-unsupported-question"])
    XCTAssertTrue(app.staticTexts["Continue on your computer"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["question-send"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Unsupported question - computer handoff"; screenshot.lifetime = .keepAlways; add(screenshot)
  }
}
