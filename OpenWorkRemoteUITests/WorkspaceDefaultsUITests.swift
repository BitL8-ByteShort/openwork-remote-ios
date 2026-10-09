import XCTest
@MainActor final class WorkspaceDefaultsUITests:XCTestCase {
 private func open(_ flags:[String] = ["-workspace-defaults"])->XCUIApplication {
  continueAfterFailure=false;let app=XCUIApplication();app.launchArguments=["-ui-testing-chats"]+flags;app.launch()
  XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:15));app.buttons["Open chat history"].tap()
  app.buttons["Settings"].tap()
  XCTAssertTrue(app.buttons["workspace-settings-open"].waitForExistence(timeout:5));app.buttons["workspace-settings-open"].tap();app.buttons["workspace-defaults-open"].tap();return app
 }
 private func chooseB(_ app:XCUIApplication){let picker=app.buttons["workspace-defaults-model"];XCTAssertTrue(picker.waitForExistence(timeout:5));picker.tap();let choice=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Model B")).firstMatch;XCTAssertTrue(choice.waitForExistence(timeout:5));choice.tap()}
 func testNewChatDefaultHasExplicitScopeAndConfirmedSave(){
  let app=open();XCTAssertTrue(app.staticTexts["workspace-defaults-scope"].waitForExistence(timeout:5));chooseB(app)
  let save=app.buttons["workspace-defaults-save"];XCTAssertTrue(save.isEnabled);save.tap()
  let current=app.staticTexts["workspace-defaults-current"];let changed=NSPredicate(format:"label CONTAINS %@","Model B");expectation(for:changed,evaluatedWith:current);waitForExpectations(timeout:8)
  let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Workspace default affecting new chats";capture.lifetime = .keepAlways;add(capture)
  XCTAssertFalse(save.isEnabled)
 }
 func testStaleSavePreservesTheSelectionAndRequiresReview(){
  let app=open(["-workspace-defaults","-stale-defaults"]);chooseB(app);app.buttons["workspace-defaults-save"].tap()
  XCTAssertTrue(app.staticTexts["workspace-defaults-notice"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["workspace-defaults-model"].label.contains("Model B"));XCTAssertFalse(app.buttons["workspace-defaults-save"].isEnabled)
  app.navigationBars.buttons["Workspace"].tap();app.navigationBars.buttons["Settings"].tap();app.navigationBars["Settings"].buttons["Done"].tap()
 }
 func testUnsupportedDeniedAndSlowDefaultReadsKeepNavigationLocal(){
  let unsupported=open([]);XCTAssertTrue(unsupported.staticTexts["Default model editing is unavailable on this computer. Update OpenWork Remote Preview or change it in OpenWork on your computer."].waitForExistence(timeout:5));unsupported.terminate()
  let denied=open(["-workspace-defaults","-defaults-denied"]);XCTAssertTrue(denied.staticTexts["workspace-defaults-notice"].waitForExistence(timeout:5));XCTAssertFalse(denied.buttons["workspace-defaults-model"].exists);denied.terminate()
  let slow=open(["-workspace-defaults","-slow-defaults"]);XCTAssertTrue(slow.staticTexts["Checking workspace defaults…"].waitForExistence(timeout:5));slow.navigationBars.buttons["Workspace"].tap();slow.navigationBars.buttons["Settings"].tap();slow.navigationBars["Settings"].buttons["Done"].tap();XCTAssertTrue(slow.buttons["Settings"].waitForExistence(timeout:3))
 }
}
