import XCTest

final class ResponsivenessTests: XCTestCase {
  @MainActor func testLargeConversationKeepsLocalNavigationAvailable() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats", "-large-conversation", "-burst-events", "-interaction-metrics"]
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 5))
    app.buttons["Open chat history"].tap()
    app.buttons["Sample chat"].tap()
    XCTAssertTrue(app.staticTexts["Large conversation fixture 499"].waitForExistence(timeout: 8))
    for _ in 0..<3 {
      app.buttons["Open chat history"].tap()
      XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
      app.buttons["Settings"].tap()
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
      app.navigationBars["Settings"].buttons["Done"].tap()
      XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
      app.navigationBars["Your chats"].buttons["Done"].tap()
      XCTAssertTrue(app.buttons["Open chat history"].isHittable)
    }
  }
  @MainActor func testSettingsRemainDismissibleWhileChatReadIsPending() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats", "-slow-messages", "-interaction-metrics"]
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 5))
    app.buttons["Open chat history"].tap()
    app.buttons["Sample chat"].tap()
    app.buttons["Open chat history"].tap()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    app.navigationBars["Settings"].buttons["Done"].tap()
    XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
    app.navigationBars["Your chats"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Open chat history"].isHittable)
  }
}
