import XCTest
import CryptoKit

final class NativeAppTests:XCTestCase {
  @MainActor private func launch(slow:Bool=false,share:Bool=false,noAnimations:Bool=false)->XCUIApplication{
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app"]+(slow ? ["-slow-native-app-settings"]:[])+(share ? ["-artifact-test-save"]:[])+(noAnimations ? ["-native-fixture-no-animations"]:[]);app.launch();return app
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
  @MainActor func testNativeRenameBlankCancelAndLongPress(){
    let app=launch(noAnimations:true)
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:4))
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Rename"].tap()
    let field=app.textFields["chat-name"]
    XCTAssertTrue(field.waitForExistence(timeout:3));field.tap();field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:11))
    XCTAssertFalse(app.buttons["save-chat-name"].isEnabled)
    field.typeText("Discard this edit");app.buttons["Cancel"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout:3));row.press(forDuration:1)
    XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout:3));app.buttons["Rename"].tap()
    XCTAssertEqual(app.textFields["chat-name"].value as? String,"Native chat")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:3))
  }
  @MainActor func testNativeVisibleRenameGroupsAndOlderTitleSearch(){
    let app=launch(noAnimations:true)
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:4))
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Rename"].tap()
    let field=app.textFields["chat-name"]
    XCTAssertTrue(field.waitForExistence(timeout:3));field.tap()
    field.press(forDuration:1)
    if app.menuItems["Select All"].waitForExistence(timeout:1){app.menuItems["Select All"].tap();field.typeText("Renamed native chat")}
    else{field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:11)+"Renamed native chat")}
    app.buttons["save-chat-name"].tap()
    XCTAssertTrue(app.buttons.containing(.staticText,identifier:"Renamed native chat").firstMatch.waitForExistence(timeout:5))
    app.buttons["groups-manage"].tap();app.buttons["native-group-new"].tap()
    let name=app.textFields["native-group-name"];XCTAssertTrue(name.waitForExistence(timeout:3));name.tap();name.typeText("Personal")
    app.buttons["native-group-save"].tap()
    XCTAssertTrue(app.staticTexts["Personal"].waitForExistence(timeout:3))
    app.buttons["native-groups-done"].tap()
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Move to group"].tap();app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-move-choice-")).firstMatch.tap()
    app.buttons["older-search-open"].tap()
    let search=app.searchFields.firstMatch;XCTAssertTrue(search.waitForExistence(timeout:3));search.tap();search.typeText("Renamed")
    XCTAssertTrue(app.buttons["native-search-hit-ses_owned"].waitForExistence(timeout:5))
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native chat rename groups and title search";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testNativeCreateForkAndExplicitTreeDeletion(){
    let app=launch()
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:4))
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Continue in a new chat"].tap()
    XCTAssertTrue(app.buttons["native-action-confirm"].waitForExistence(timeout:3));app.buttons["native-action-confirm"].tap()
    XCTAssertTrue(app.buttons["Model and chat settings"].waitForExistence(timeout:5))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_fork"].waitForExistence(timeout:4));app.buttons["chat-actions-ses_fork"].tap()
    app.buttons["Delete chat and branches"].tap()
    XCTAssertTrue(app.staticTexts["1 chat in this tree"].waitForExistence(timeout:4))
    app.buttons["native-action-confirm"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["chat-actions-ses_fork"].exists)
    app.buttons["native-list-new-chat"].tap()
    XCTAssertTrue(app.buttons["Model and chat settings"].waitForExistence(timeout:5))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons.containing(.staticText,identifier:"New chat").firstMatch.waitForExistence(timeout:4))
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
