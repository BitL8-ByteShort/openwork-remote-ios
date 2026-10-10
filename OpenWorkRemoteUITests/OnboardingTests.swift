import XCTest

final class OnboardingTests: XCTestCase {
  @MainActor func testRevokedAccessOffersFreshPairingInsteadOfRetrying() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-onboarding", "-ui-testing-revoked"]
    app.launch()
    XCTAssertTrue(app.buttons["pair-again"].waitForExistence(timeout: 5))
    app.buttons["pair-again"].tap()
    XCTAssertTrue(app.buttons["scan-pairing"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["paste-pairing"].exists)
    XCTAssertFalse(app.buttons["pair-again"].exists)
  }
  @MainActor func testPairingInputPreservesLiteralCharacters() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-onboarding"]
    app.launch()
    XCTAssertTrue(app.buttons["get-started"].waitForExistence(timeout: 5))
    app.buttons["get-started"].tap()
    app.buttons["computer-ready"].tap()
    app.buttons["paste-pairing"].tap()
    let field = app.textViews["pairing-payload"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.tap()
    let literal = #"{"test":"two--dashes","host":"host-name.test"}"#
    field.typeText(literal)
    XCTAssertEqual(field.value as? String, literal)
  }
  @MainActor func testGuidedSetupAndInvalidPaste() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-onboarding"]
    app.launch()
    XCTAssertTrue(app.buttons["get-started"].waitForExistence(timeout: 5))
    app.buttons["get-started"].tap()
    app.buttons["computer-ready"].tap()
    app.buttons["paste-pairing"].tap()
    let field = app.textViews["pairing-payload"]
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.tap()
    field.typeText("invalid pairing")
    app.buttons["connect-payload"].tap()
    XCTAssertTrue(
      app.otherElements["pairing-error"].waitForExistence(timeout: 3)
        || app.staticTexts["That pairing code is invalid. Create a new code on your computer."]
          .exists
    )
  }
}
