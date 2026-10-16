import XCTest

final class NativeOnboardingTests:XCTestCase {
  @MainActor private func launch(largestText:Bool=false)->XCUIApplication {
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-onboarding"]
    if largestText{app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
    app.launchForNativeWindowQualification();return app
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
  @MainActor func testPasswordRouteReviewsBeforeConnectingAndClearsRejectedSecret(){
    continueAfterFailure=false
    let app=launch();openPassword(app)
    let address=app.textFields["native-server-address"],password=app.secureTextFields["native-server-password-value"]
    address.tap();address.typeText("https://synthetic.example\n")
    password.typeText("synthetic-server-password")
    let review=app.buttons["native-review-server-password"]
    if !review.isHittable{app.scrollViews.firstMatch.swipeUp()}
    review.tap()
    XCTAssertTrue(app.staticTexts["native-password-reviewed-origin"].waitForExistence(timeout:3))
    XCTAssertFalse(app.progressIndicators["native-connecting"].exists)
    // iOS may offer its own Passwords save choice as secure entry ends.
    // Never save the synthetic server credential during qualification.
    dismissSystemPasswordSave(app)
    let connect=app.buttons["native-confirm-server-password"]
    if !connect.isHittable{app.scrollViews.firstMatch.swipeUp()}
    XCTAssertTrue(connect.isHittable);connect.tap()
    XCTAssertTrue(app.staticTexts["native-password-error"].waitForExistence(timeout:5))
    XCTAssertTrue(password.waitForExistence(timeout:3))
    XCTAssertTrue(["","Server password"].contains(password.value as? String ?? "unexpected"))
    XCTAssertFalse(app.buttons["native-review-server-password"].isEnabled)
  }
  @MainActor func testBackgroundClearsTheServerPasswordDraft(){
    continueAfterFailure=false
    let app=launch();openPassword(app)
    let password=app.secureTextFields["native-server-password-value"]
    password.tap();password.typeText("synthetic-server-password")
    XCUIDevice.shared.press(.home);app.activate()
    XCTAssertTrue(password.waitForExistence(timeout:5))
    XCTAssertTrue(["","Server password"].contains(password.value as? String ?? "unexpected"))
  }
  @MainActor func testPasswordReviewAtLargestTextCanCancelAndClearsTheSecret(){
    continueAfterFailure=false
    let app=launch(largestText:true);openPassword(app)
    let address=app.textFields["native-server-address"],password=app.secureTextFields["native-server-password-value"]
    for _ in 0..<6{if address.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
    // Use the form's Next action; the software keyboard can cover the
    // field's center on a small phone even when XCTest calls it hittable.
    address.tap();address.typeText("https://synthetic.example\n")
    password.typeText("synthetic-server-password")
    app.buttons["native-review-server-password"].tap()
    XCTAssertTrue(app.staticTexts["native-password-reviewed-origin"].waitForExistence(timeout:3))
    dismissSystemPasswordSave(app)
    XCUIDevice.shared.orientation = .landscapeLeft
    defer{XCUIDevice.shared.orientation = .portrait}
    let cancel=app.buttons["native-cancel-server-password"]
    for _ in 0..<8{if cancel.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
    XCTAssertTrue(cancel.isHittable)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Password review largest text landscape";proof.lifetime = .keepAlways;add(proof)
    cancel.tap()
    let option=app.buttons["native-server-password"]
    for _ in 0..<8{if option.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
    XCTAssertTrue(option.isHittable);option.tap()
    XCTAssertTrue(password.waitForExistence(timeout:3))
    XCTAssertTrue(["","Server password"].contains(password.value as? String ?? "unexpected"))
    XCTAssertFalse(app.buttons["native-review-server-password"].isEnabled)
  }
  @MainActor private func dismissSystemPasswordSave(_ app:XCUIApplication){
    // UIKit exposes this as Alert on iPad and Sheet on iPhone.
    let alert=app.alerts["Save Password?"],sheet=app.sheets["Save Password?"]
    let container:XCUIElement?
    if alert.waitForExistence(timeout:2){container=alert}
    else if sheet.waitForExistence(timeout:2){container=sheet}
    else{container=nil}
    guard let container else{return}
    let decline=container.buttons["Not Now"]
    XCTAssertTrue(decline.waitForExistence(timeout:3))
    let actions=container.scrollViews.containing(.button,identifier:"Not Now").firstMatch
    for _ in 0..<3{
      if decline.isHittable{break}
      guard actions.exists else{break};actions.swipeUp()
    }
    guard decline.isHittable else{
      let proof=XCTAttachment(string:app.debugDescription);proof.name="System password save hierarchy";proof.lifetime = .keepAlways;add(proof)
      XCTFail("Decline the system password-save choice before continuing; never save qualification credentials.");return
    }
    decline.tap()
  }
  @MainActor private func openPassword(_ app:XCUIApplication){
    XCTAssertTrue(app.buttons["native-get-started"].waitForExistence(timeout:5))
    app.buttons["native-get-started"].tap();app.buttons["native-computer-ready"].tap()
    let option=app.buttons["native-server-password"]
    XCTAssertTrue(option.waitForExistence(timeout:3))
    for _ in 0..<4{if option.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
    XCTAssertTrue(option.isHittable);option.tap()
    XCTAssertTrue(app.textFields["native-server-address"].waitForExistence(timeout:3))
  }
  @MainActor private func openPaste(_ app:XCUIApplication) {
    XCTAssertTrue(app.buttons["native-get-started"].waitForExistence(timeout:5))
    app.buttons["native-get-started"].tap();app.buttons["native-computer-ready"].tap();app.buttons["native-paste-pairing"].tap()
    XCTAssertTrue(app.textViews["native-pairing-payload"].waitForExistence(timeout:3))
  }
}
