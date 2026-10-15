import XCTest

final class NativeStartupTests:XCTestCase{
  @MainActor func testNativeWelcomeAndLegalWorkBeforePairingAtLargestText(){
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication()
    app.launchArguments=["-ui-testing-native-startup","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
    app.launchForNativeWindowQualification()
    let start=app.buttons["native-get-started"]
    XCTAssertTrue(start.waitForExistence(timeout:6))
    app.buttons["native-about-open"].tap()
    XCTAssertTrue(app.staticTexts["about-name"].waitForExistence(timeout:4))
    XCTAssertTrue(app.staticTexts["about-version"].exists)
    let privacy=app.buttons["about-privacy"]
    for _ in 0..<10{if privacy.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(privacy.isHittable);privacy.tap()
    XCTAssertTrue(app.scrollViews["information-document-privacy"].waitForExistence(timeout:3))
    XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","2026-10-15.1")).firstMatch.exists)
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Native offline privacy largest text";proof.lifetime = .keepAlways;add(proof)
    app.navigationBars["Privacy policy"].buttons.element(boundBy:0).tap()
    XCTAssertTrue(app.buttons["native-about-done"].waitForExistence(timeout:3))
    app.buttons["native-about-done"].tap()
    XCTAssertTrue(start.waitForExistence(timeout:3))
    for _ in 0..<14{if start.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(start.isHittable);start.tap()
    XCTAssertTrue(app.buttons["native-computer-ready"].waitForExistence(timeout:3))
    XCTAssertTrue(app.buttons["native-back"].isHittable)
    app.buttons["native-back"].tap()
    XCTAssertTrue(start.waitForExistence(timeout:3))
  }
}
