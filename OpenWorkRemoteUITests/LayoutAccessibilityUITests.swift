import XCTest

// Run these shipping views on compact iPhone and iPad destinations as well as
// the normal phone. Fixtures contain only synthetic data and no host credential.
final class LayoutAccessibilityUITests: XCTestCase {
  @MainActor private func launch(_ arguments: [String], largestText: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments
    if largestText {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }
    app.launch()
    return app
  }

  @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<12 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.exists && element.isHittable, "Expected a reachable control: \(element)")
  }

  @MainActor private func capture(_ name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor private func audit(_ app: XCUIApplication) throws {
    // Structural audits complement the explicit largest-text journeys below.
    // Apple's full predictive font/contrast audit has separate saved findings;
    // passing this subset does not clear those or qualify physical VoiceOver.
    try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .hitRegion, .trait]) { issue in
      print("Accessibility issue: \(issue.compactDescription); \(issue.element?.debugDescription ?? "no element"); \(issue.detailedDescription)")
      return false
    }
  }

  @MainActor func testLargestTextWelcomeHistoryAndSettingsRemainReachable() {
    let app = launch(["-ui-testing-information", "-ui-testing-onboarding"], largestText: true)
    let start = app.buttons["get-started"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    capture("PocketWork welcome largest text top", app: app)
    reveal(start, in: app)
    capture("PocketWork welcome largest text action", app: app)
    let about = app.buttons["welcome-about"]
    reveal(about, in: app)
    about.tap()
    XCTAssertTrue(app.staticTexts["about-name"].waitForExistence(timeout: 3))
    capture("PocketWork about largest text", app: app)
    app.terminate()

    app.launchArguments = ["-ui-testing-chats", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    history.tap()
    let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch
    reveal(chat, in: app)
    capture("PocketWork history largest text", app: app)
    XCTAssertGreaterThan(chat.frame.height, 44)
    let settings = app.buttons["Settings"]
    XCTAssertTrue(settings.isHittable)
    settings.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    let aboutSettings = app.buttons["settings-about"]
    reveal(aboutSettings, in: app)
    capture("PocketWork settings largest text", app: app)
    let done = app.navigationBars["Settings"].buttons["Done"]
    XCTAssertTrue(done.isHittable)
    done.tap()
    XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
  }

  @MainActor func testWelcomeAccessibilityAudit() throws {
    let app = launch(["-ui-testing-information", "-ui-testing-onboarding"])
    XCTAssertTrue(app.buttons["get-started"].waitForExistence(timeout: 5))
    try audit(app)
    capture("PocketWork welcome accessibility", app: app)
  }

  @MainActor func testHistoryAndChatAccessibilityAudit() throws {
    let app = launch(["-ui-testing-chats", "-slow-questions"])
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    history.tap()
    XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
    let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch
    reveal(chat, in: app)
    // Audit the row after scrolling it clear of the native bottom toolbar.
    app.swipeUp()
    try audit(app)
    capture("PocketWork history accessibility", app: app)
    chat.tap()
    XCTAssertTrue(app.staticTexts["Chat is ready."].waitForExistence(timeout: 5))
    try audit(app)
    capture("PocketWork conversation accessibility", app: app)
  }

  @MainActor func testLargestTextQuestionAndKeyboardKeepControlsReachable() {
    let app = launch(["-ui-testing-chats", "-pending-question"], largestText: true)
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    history.tap()
    let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch
    reveal(chat, in: app)
    chat.tap()
    let question = app.buttons["question-banner"]
    XCTAssertTrue(question.waitForExistence(timeout: 5))
    reveal(question, in: app)
    question.tap()
    let option = app.buttons["question-option-detailed"]
    reveal(option, in: app)
    option.tap()
    let next = app.buttons["question-next"]
    reveal(next, in: app)
    XCTAssertTrue(next.isEnabled)
    capture("PocketWork question largest text", app: app)
    next.tap()
    let input = app.textFields["question-text-name"]
    reveal(input, in: app)
    input.tap()
    input.typeText("Layout test draft")
    XCTAssertTrue(app.buttons["Cancel"].isHittable)
    capture("PocketWork question keyboard largest text", app: app)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(question.waitForExistence(timeout: 3))
    question.tap()
    reveal(next, in: app)
    next.tap()
    XCTAssertEqual(input.value as? String, "Layout test draft")
    XCTAssertTrue(app.buttons["Cancel"].isHittable)
  }
}
