import XCTest

final class DataControlsUITests: XCTestCase {
  @MainActor private func controls() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-data-controls"]
    app.launch()
    let about = app.buttons["welcome-about"]
    for _ in 0..<8 { if about.exists && about.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(about.waitForExistence(timeout: 5))
    about.tap()
    let controls = app.buttons["about-data-controls"]
    for _ in 0..<8 { if controls.exists && controls.isHittable { break }; app.swipeUp() }
    controls.tap()
    return app
  }
  @MainActor func testCancelDoesNotResetAndClearDraftsIsSeparate() {
    let app = controls()
    app.buttons["local-data-reset"].tap()
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["local-data-reset"].exists)
    XCTAssertFalse(app.staticTexts["welcome-reset-report"].exists)
    app.buttons["local-data-drafts"].tap()
    app.buttons["Clear drafts"].tap()
    XCTAssertTrue(app.staticTexts["local-data-result"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["local-data-result"].label.contains("Unsent drafts were cleared"))
    XCTAssertTrue(app.buttons["local-data-reset"].exists)
  }
  @MainActor func testConfirmedResetReturnsToUnpairedWelcomeWithReport() {
    let app = controls()
    app.buttons["local-data-reset"].tap()
    app.buttons["Reset local data"].tap()
    XCTAssertTrue(app.staticTexts["welcome-reset-report"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["welcome-reset-report"].label.contains("original files were not deleted"))
    let getStarted = app.buttons["get-started"]
    for _ in 0..<10 { if getStarted.exists && getStarted.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(getStarted.isHittable)
  }
}
