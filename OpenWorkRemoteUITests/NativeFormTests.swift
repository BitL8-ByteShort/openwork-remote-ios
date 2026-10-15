import XCTest
final class NativeFormTests:XCTestCase {
  @MainActor private func launch(_ arguments:[String]=[])->XCUIApplication{
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-forms"]+arguments;app.launch();return app
  }
  @MainActor func testConditionalIntegerValidationAndExplicitSubmit(){
    let app=launch()
    XCTAssertTrue(app.buttons["native-form-option-detailed"].waitForExistence(timeout:6))
    app.buttons["native-form-option-detailed"].tap();app.buttons["native-form-next"].tap()
    XCTAssertTrue(app.textFields["native-form-number"].waitForExistence(timeout:3))
    app.textFields["native-form-number"].tap();app.textFields["native-form-number"].typeText("1.5")
    app.buttons["native-form-keyboard-done"].tap();app.buttons["native-form-submit"].tap()
    XCTAssertTrue(app.staticTexts["native-form-validation"].waitForExistence(timeout:3))
    app.textFields["native-form-number"].tap();app.textFields["native-form-number"].typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:3)+"2")
    app.buttons["native-form-keyboard-done"].tap();app.buttons["native-form-submit"].tap()
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:3))
  }
  @MainActor func testClosingKeepsDraftAndLostReplyCannotAutomaticallyResend(){
    let app=launch(["-native-form-uncertain"])
    XCTAssertTrue(app.buttons["native-form-option-simple"].waitForExistence(timeout:6))
    app.buttons["native-form-option-simple"].tap();app.buttons["native-form-close"].tap();app.buttons["native-form-open"].tap()
    XCTAssertTrue(app.buttons["native-form-option-simple"].waitForExistence(timeout:3))
    XCTAssertTrue(app.buttons["native-form-option-simple"].isSelected)
    app.buttons["native-form-submit"].tap()
    XCTAssertTrue(app.staticTexts["native-form-uncertain"].waitForExistence(timeout:3))
    XCTAssertFalse(app.buttons["native-form-submit"].isEnabled)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native uncertain answer recovery";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testExternalFormRequiresReviewedComputerHandoff(){
    let app=launch(["-native-form-external"])
    XCTAssertTrue(app.staticTexts["Continue on your computer"].waitForExistence(timeout:6))
    XCTAssertFalse(app.buttons["native-form-submit"].exists)
    app.buttons["Review external link"].tap()
    XCTAssertTrue(app.staticTexts["https://synthetic.example/review"].waitForExistence(timeout:3))
    XCTAssertTrue(app.buttons["Open in browser"].exists)
    app.buttons["native-external-review-cancel"].tap()
    XCTAssertTrue(app.staticTexts["Continue on your computer"].exists)
  }
  @MainActor func testDesktopChangeRequiresReviewOfLatestQuestion(){
    let app=launch(["-native-form-changed"])
    XCTAssertTrue(app.buttons["native-form-option-simple"].waitForExistence(timeout:6))
    app.buttons["native-form-option-simple"].tap();app.buttons["native-form-submit"].tap()
    XCTAssertTrue(app.buttons["Review latest question"].waitForExistence(timeout:3))
    XCTAssertFalse(app.buttons["native-form-submit"].isEnabled)
    app.buttons["Review latest question"].tap()
    XCTAssertTrue(app.staticTexts["Updated question"].waitForExistence(timeout:3))
    XCTAssertFalse(app.buttons["native-form-option-simple"].isSelected)
  }
}
