import XCTest

// Run explicitly when investigating performance; use the bounded five-minute
// window with optimized DEBUG code and synthetic data. No real pairing loads.
final class PerformanceStressTests: XCTestCase {
  @MainActor func testFiveMinuteLargeConversationAndReconnectStress() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats", "-large-conversation", "-burst-events",
      "-offline-reconnect", "-interaction-metrics"]
    app.launch()
    XCTAssertTrue(app.buttons["Sample chat"].exists || app.buttons["Open chat history"].waitForExistence(timeout: 8))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["Sample chat"].waitForExistence(timeout: 10))
    app.buttons["Sample chat"].tap()
    XCTAssertTrue(app.staticTexts["Large conversation fixture 499"].waitForExistence(timeout: 10))
    let deadline = Date().addingTimeInterval(300)
    var cycles = 0
    while Date() < deadline {
      app.buttons["Open chat history"].tap()
      XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
      app.buttons["Settings"].tap()
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
      app.navigationBars["Settings"].buttons["Done"].tap()
      XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout: 3))
      if cycles % 3 == 0 { app.buttons["Sample chat"].tap() }
      else { app.navigationBars["Your chats"].buttons["Done"].tap() }
      XCTAssertTrue(app.buttons["Open chat history"].isHittable)
      cycles += 1
    }
    XCTAssertGreaterThan(cycles, 10)
    let attachment = XCTAttachment(string: "Synthetic navigation cycles: \(cycles); duration: 300 seconds. XCTest round trips are not app latency.")
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
