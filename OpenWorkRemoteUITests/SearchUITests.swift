import XCTest

@MainActor final class SearchUITests: XCTestCase {
  private func open(_ options: [String] = ["-older-search"]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats"] + options
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 15))
    app.buttons["Open chat history"].tap()
    let open = app.buttons["older-search-open"]
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    open.tap()
    return app
  }
  func testOlderTitleResultsContinueWithoutChangingLoadedListAndOpenImmediately() {
    let app = open()
    let field = app.textFields["older-search-query"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("homepage")
    let match = app.buttons["older-search-result-ses_older"]
    XCTAssertTrue(match.waitForExistence(timeout: 5))
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Older-title search with incomplete coverage"
    capture.lifetime = .keepAlways
    add(capture)
    app.buttons["older-search-more"].tap()
    XCTAssertTrue(
      app.staticTexts["Checked 520 chat titles · Search complete"].waitForExistence(timeout: 5))
    match.tap()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.textFields["older-search-query"].exists)
  }
  func testAnUnfinishedEmptySearchOffersContinuationBeforeNoMatches() {
    let app = open()
    let field = app.textFields["older-search-query"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("none")
    XCTAssertTrue(app.buttons["older-search-more"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["older-search-empty"].exists)
    app.buttons["older-search-more"].tap()
    XCTAssertTrue(app.staticTexts["older-search-empty"].waitForExistence(timeout: 5))
  }
  func testUnsupportedAndSlowSearchKeepBackAndDoneLocal() {
    let unsupported = open([])
    XCTAssertTrue(
      unsupported.staticTexts[
        "Older-title search is unavailable on this computer. Update OpenWork Remote Preview or search in OpenWork on your computer."
      ].waitForExistence(timeout: 5))
    unsupported.navigationBars.buttons["Your chats"].tap()
    unsupported.buttons["Done"].tap()
    XCTAssertTrue(unsupported.buttons["Open chat history"].waitForExistence(timeout: 3))
    unsupported.terminate()
    let slow = open(["-older-search", "-slow-title-search"])
    let field = slow.textFields["older-search-query"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("home")
    XCTAssertTrue(slow.staticTexts["Checking chat titles…"].waitForExistence(timeout: 5))
    slow.navigationBars.buttons["Your chats"].tap()
    slow.buttons["Done"].tap()
    XCTAssertTrue(slow.buttons["Open chat history"].waitForExistence(timeout: 3))
  }
}
