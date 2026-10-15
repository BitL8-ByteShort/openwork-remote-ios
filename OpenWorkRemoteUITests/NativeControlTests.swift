import XCTest

final class NativeControlTests:XCTestCase {
  @MainActor private func launch(slow:Bool=false)->XCUIApplication {
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-controls"]+(slow ? ["-slow-native-settings"] : []);app.launch();return app
  }
  @MainActor func testSameModelIDAcrossProvidersAndVariantReadback() {
    let app=launch()
    XCTAssertTrue(app.buttons["native-model-picker"].waitForExistence(timeout:8))
    app.buttons["native-model-picker"].tap()
    XCTAssertTrue(app.buttons.containing(.staticText,identifier:"Model B").firstMatch.waitForExistence(timeout:3))
    app.buttons.containing(.staticText,identifier:"Model B").firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Provider B"].exists)
    app.buttons["native-model-apply"].tap()
    XCTAssertTrue(app.staticTexts["Model B"].waitForExistence(timeout:3))
    XCTAssertFalse(app.buttons["native-model-apply"].isEnabled)
    app.buttons["native-settings-done"].tap()
    XCTAssertTrue(app.staticTexts["native-settings-home"].waitForExistence(timeout:2))
  }
  @MainActor func testDoneDoesNotWaitForThirtySecondSettingsRead() {
    let app=launch(slow:true)
    XCTAssertTrue(app.buttons["native-settings-done"].waitForExistence(timeout:5))
    let start=Date();app.buttons["native-settings-done"].tap()
    XCTAssertTrue(app.staticTexts["native-settings-home"].waitForExistence(timeout:2))
    XCTAssertLessThan(Date().timeIntervalSince(start),3)
  }
  @MainActor func testRulesPreserveDenyAndRequireAllowReview() {
    let app=launch()
    XCTAssertTrue(app.buttons["native-model-picker"].waitForExistence(timeout:8))
    if !app.buttons["Permissions"].isHittable{app.swipeUp()}
    app.buttons["Permissions"].tap()
    XCTAssertTrue(app.buttons["native-session-rules"].waitForExistence(timeout:3))
    app.buttons["native-session-rules"].tap()
    XCTAssertTrue(app.textFields["Rule action"].waitForExistence(timeout:3))
    XCTAssertEqual(app.textFields["Rule action"].firstMatch.value as? String,"read")
    app.buttons["native-rule-effect"].firstMatch.tap();app.buttons["Allow"].tap()
    app.buttons["native-rules-save"].tap()
    XCTAssertTrue(app.buttons["native-allow-confirm"].waitForExistence(timeout:3))
    XCTAssertTrue(app.staticTexts["read\n*.env"].exists)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["native-rules-save"].exists)
    app.buttons["native-rules-save"].tap();app.buttons["native-allow-confirm"].tap()
    XCTAssertTrue(app.buttons["native-session-rules"].waitForExistence(timeout:3))
    XCTAssertTrue(app.staticTexts["Allow"].exists)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native permission sections";proof.lifetime = .keepAlways;add(proof)
  }
}
