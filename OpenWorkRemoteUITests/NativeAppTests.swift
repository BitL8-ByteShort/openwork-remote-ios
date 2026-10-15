import XCTest

final class NativeAppTests:XCTestCase {
  @MainActor private func launch(slow:Bool=false)->XCUIApplication{
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app"]+(slow ? ["-slow-native-app-settings"]:[]);app.launch();return app
  }
  @MainActor func testNativeConversationUsesExistingChatAndSettingsScreens(){
    let app=launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.staticTexts["Native project"].waitForExistence(timeout:3))
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:4))
    XCTAssertEqual(app.textFields["composer"].placeholderValue,"Message OpenCode")
    XCTAssertTrue(app.buttons["native-approval-open"].waitForExistence(timeout:4))
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:4))
    app.buttons["native-form-open"].tap()
    XCTAssertTrue(app.navigationBars["Answer OpenCode"].waitForExistence(timeout:4))
    app.buttons["native-form-close"].tap()
    app.buttons["Model and chat settings"].tap()
    XCTAssertTrue(app.buttons["native-model-picker"].waitForExistence(timeout:4))
    app.buttons["native-settings-done"].tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native shared conversation shell";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testNativeDoneRemainsIndependentOfSlowCatalog(){
    let app=launch(slow:true)
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:4))
    app.buttons["Model and chat settings"].tap()
    XCTAssertTrue(app.buttons["native-settings-done"].waitForExistence(timeout:3))
    app.buttons["native-settings-done"].tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
    app.buttons["native-approval-open"].tap()
    XCTAssertTrue(app.buttons["Allow once"].waitForExistence(timeout:3))
    app.buttons["Done"].tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
  }
}
