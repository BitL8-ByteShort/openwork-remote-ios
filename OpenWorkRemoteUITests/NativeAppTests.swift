import XCTest
import CryptoKit

final class NativeAppTests:XCTestCase {
  @MainActor private func launch(slow:Bool=false,share:Bool=false)->XCUIApplication{
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app"]+(slow ? ["-slow-native-app-settings"]:[])+(share ? ["-artifact-test-save"]:[]);app.launch();return app
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
  @MainActor func testNativePhotoSelectionAndFileOnlySend(){
    let app=launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    XCTAssertTrue(app.buttons["composer-add"].waitForExistence(timeout:4))
    app.buttons["composer-add"].tap();app.buttons["Photos or files"].tap()
    XCTAssertTrue(app.buttons["Choose photos"].waitForExistence(timeout:4))
    let sample=app.buttons["native-fixture-photo"]
    if !sample.isHittable{app.swipeUp()}
    sample.tap()
    XCTAssertTrue(app.staticTexts["Ready · inline media"].waitForExistence(timeout:5))
    app.buttons["native-attachment-done"].tap()
    let chips=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-attachment-chip-"))
    XCTAssertEqual(chips.count,1)
    XCTAssertTrue(app.buttons["send-message"].isEnabled)
    app.buttons["send-message"].tap()
    let removed=NSPredicate{_,_ in chips.count==0}
    expectation(for:removed,evaluatedWith:nil)
    waitForExpectations(timeout:5)
  }

  @MainActor private func openResults(_ app:XCUIApplication){
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    let files=app.buttons["Files from this chat"]
    XCTAssertTrue(files.waitForExistence(timeout:4));files.tap()
  }
  @MainActor func testNativeResultPreviewAndExplicitShare(){
    let app=launch(share:true);openResults(app)
    let file=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-result-row-")).firstMatch
    XCTAssertTrue(file.waitForExistence(timeout:4));file.tap()
    XCTAssertTrue(app.staticTexts["Synthetic generated result\n"].waitForExistence(timeout:4))
    if app.frame.width>700{
      XCUIDevice.shared.orientation = .landscapeLeft
      let rotated=expectation(for:NSPredicate{_,_ in app.frame.width>app.frame.height},evaluatedWith:nil)
      wait(for:[rotated],timeout:5)
      XCTAssertTrue(app.buttons["native-result-share"].waitForExistence(timeout:3))
    }
    let share=app.buttons["native-result-share"]
    if !share.isHittable{app.swipeUp()}
    XCTAssertTrue(share.isEnabled);share.tap()
    let save=app.cells["Save test copy"]
    XCTAssertTrue(save.waitForExistence(timeout:8))
    let actionable=expectation(for:NSPredicate(format:"hittable == true AND enabled == true"),evaluatedWith:save)
    wait(for:[actionable],timeout:5)
    save.press(forDuration:0.3)
    let saved=app.staticTexts["native-result-test-saved"]
    XCTAssertTrue(saved.waitForExistence(timeout:8))
    let expected=SHA256.hash(data:Data("Synthetic generated result\n".utf8)).map{String(format:"%02x",$0)}.joined()
    XCTAssertTrue(saved.label.contains(expected))
    XCTAssertTrue(app.staticTexts["Synthetic generated result\n"].exists)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native result preview after explicit share";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testExplicitProjectFileBrowser(){
    let app=launch();openResults(app)
    app.buttons["native-project-files"].tap()
    XCTAssertTrue(app.buttons["project-only.txt"].waitForExistence(timeout:4));app.buttons["project-only.txt"].tap()
    XCTAssertTrue(app.staticTexts["Selected project file\n"].waitForExistence(timeout:4))
  }

}
