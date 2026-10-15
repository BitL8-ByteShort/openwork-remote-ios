import XCTest

final class NativeOnboardingTests:XCTestCase {
  @MainActor private func launch()->XCUIApplication {
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-onboarding"];app.launchForNativeWindowQualification();return app
  }
  @MainActor func testWelcomeExplainsNativePairing() {
    let app=launch()
    XCTAssertTrue(app.staticTexts["native-welcome-copy"].waitForExistence(timeout:5))
    XCTAssertTrue(app.buttons["native-get-started"].exists)
    app.buttons["native-get-started"].tap()
    XCTAssertTrue(app.buttons["native-computer-ready"].waitForExistence(timeout:3))
    app.buttons["native-computer-ready"].tap()
    XCTAssertTrue(app.buttons["native-scan-pairing"].exists)
    XCTAssertTrue(app.buttons["native-paste-pairing"].exists)
  }
  @MainActor func testLinkReviewRequiresExplicitConnectAndCanCancel() {
    let app=launch();openPaste(app)
    app.textViews["native-pairing-payload"].tap()
    app.textViews["native-pairing-payload"].typeText("https://synthetic.example/auth/connect/synthetic_code")
    app.buttons["native-review-payload"].tap()
    XCTAssertTrue(app.staticTexts["native-reviewed-origin"].waitForExistence(timeout:3))
    XCTAssertTrue(app.buttons["native-confirm-connection"].exists)
    XCTAssertFalse(app.progressIndicators["native-connecting"].exists)
    app.buttons["native-cancel-review"].tap()
    XCTAssertTrue(app.buttons["native-paste-pairing"].waitForExistence(timeout:3))
  }
  @MainActor func testInvalidPasteDoesNotLeaveThePhone() {
    let app=launch();openPaste(app)
    app.textViews["native-pairing-payload"].tap()
    app.textViews["native-pairing-payload"].typeText("not a native pairing payload")
    app.buttons["native-review-payload"].tap()
    XCTAssertTrue(app.staticTexts["native-pairing-error"].waitForExistence(timeout:3))
    XCTAssertFalse(app.buttons["native-confirm-connection"].exists)
  }
  @MainActor func testRejectedCodeRequiresFreshInputInsteadOfReplayingConnect() {
    continueAfterFailure=false
    let app=launch();openPaste(app)
    let field=app.textViews["native-pairing-payload"]
    field.tap();field.typeText("https://synthetic.example/auth/connect/synthetic_code")
    app.buttons["native-review-payload"].tap()
    let connect=app.buttons["native-confirm-connection"]
    XCTAssertTrue(connect.waitForExistence(timeout:3));connect.tap()
    XCTAssertTrue(app.staticTexts["native-pairing-error"].waitForExistence(timeout:5))
    XCTAssertFalse(connect.exists,"A rejected single-use code must not be offered again")
    let fresh=app.buttons["native-fresh-pairing-code"]
    XCTAssertTrue(fresh.waitForExistence(timeout:3));fresh.tap()
    XCTAssertTrue(app.buttons["native-paste-pairing"].waitForExistence(timeout:3))
    XCTAssertFalse(app.staticTexts["native-reviewed-origin"].exists)
    app.buttons["native-paste-pairing"].tap()
    XCTAssertTrue(field.waitForExistence(timeout:3))
    XCTAssertEqual(field.value as? String,"")
    field.tap();field.typeText("https://synthetic.example/auth/connect/fresh_synthetic_code")
    app.buttons["native-review-payload"].tap()
    XCTAssertTrue(connect.waitForExistence(timeout:3))
    XCTAssertFalse(app.staticTexts["native-pairing-error"].exists)
    app.buttons["native-cancel-review"].tap()
  }
  @MainActor func testRotationRetainsOriginReview() {
    let app=launch();openPaste(app)
    app.textViews["native-pairing-payload"].tap()
    app.textViews["native-pairing-payload"].typeText("https://synthetic.example/auth/connect/synthetic_code")
    app.buttons["native-review-payload"].tap()
    XCTAssertTrue(app.staticTexts["native-reviewed-origin"].waitForExistence(timeout:3))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(app.buttons["native-confirm-connection"].waitForExistence(timeout:3))
    if !app.buttons["native-confirm-connection"].isHittable { app.windows.firstMatch.swipeUp() }
    XCTAssertTrue(app.buttons["native-confirm-connection"].isHittable)
    XCTAssertTrue(app.staticTexts["native-reviewed-origin"].exists)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native origin review landscape";proof.lifetime = .keepAlways;add(proof)
    XCUIDevice.shared.orientation = .portrait
  }
  @MainActor private func openPaste(_ app:XCUIApplication) {
    XCTAssertTrue(app.buttons["native-get-started"].waitForExistence(timeout:5))
    app.buttons["native-get-started"].tap();app.buttons["native-computer-ready"].tap();app.buttons["native-paste-pairing"].tap()
    XCTAssertTrue(app.textViews["native-pairing-payload"].waitForExistence(timeout:3))
  }
}
