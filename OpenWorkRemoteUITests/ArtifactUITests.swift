import XCTest

@MainActor final class ArtifactUITests: XCTestCase {
  private func open(_ options: [String] = []) -> XCUIApplication {
    let app=XCUIApplication();app.launchArguments=["-ui-testing-chats","-artifacts"]+options;app.launch()
    let history=app.buttons["Open chat history"];XCTAssertTrue(history.waitForExistence(timeout:15));history.tap()
    let chat=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Sample chat")).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout:5));chat.tap()
    app.buttons["Model and chat settings"].tap()
    let files=app.buttons["chat-files-settings"];XCTAssertTrue(files.waitForExistence(timeout:5));files.tap()
    return app
  }
  func testTextPreviewRequiresSelectionAndProvidesExplicitShareAction() {
    let app=open()
    let row=app.buttons["artifact-row-art_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    XCTAssertTrue(row.waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["Generated result fixture."].exists);row.tap()
    XCTAssertTrue(app.staticTexts["Generated result fixture."].waitForExistence(timeout:5))
    XCTAssertTrue(app.buttons["Share or save a copy"].isEnabled)
  }
  func testResultsRemainAccessibleAfterAChatWithOneVeryLongMessage() {
    let app=open(["-long-result-chat"])
    XCTAssertTrue(app.buttons["artifact-row-art_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].waitForExistence(timeout:5))
    app.buttons["artifact-done"].tap()
    app.buttons["Done"].tap()
    // Files navigation stays in the fixed header even when long history is virtualized.
    XCTAssertTrue(app.buttons["Model and chat settings"].isHittable)
    XCTAssertFalse(app.buttons["Files from this chat"].exists)
    app.buttons["Model and chat settings"].tap()
    XCTAssertTrue(app.buttons["chat-files-settings"].exists)
  }
  func testNativeShareSheetSavesOneExplicitlySelectedCopyAndRetainsThePreview() {
    let app=open(["-artifact-test-save"])
    app.buttons["artifact-row-art_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].tap()
    XCTAssertTrue(app.staticTexts["Generated result fixture."].waitForExistence(timeout:5))
    app.buttons["Share or save a copy"].tap()
    let save=app.cells["Save test copy"];XCTAssertTrue(save.waitForExistence(timeout:10));save.tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Test copy saved:")).firstMatch.waitForExistence(timeout:10))
    XCTAssertTrue(app.staticTexts["Generated result fixture."].exists)
    XCTAssertTrue(app.buttons["Share or save a copy"].isEnabled)
  }
  func testDeniedGrantExplainsComputerControlAndDoneDismisses() {
    let app=open(["-attachment-denied"])
    XCTAssertTrue(app.staticTexts["File access is not allowed for this phone. Allow file transfer in Remote access on your computer."].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["artifact-row-art_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].exists)
    app.buttons["artifact-done"].tap()
    app.buttons["Done"].tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
  }
  func testChangedFileNeverOffersAnIncompleteShare() {
    let app=open(["-artifact-changed"])
    let row=app.buttons["artifact-row-art_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
    XCTAssertTrue(app.staticTexts["This file changed or is no longer available. Refresh the files and try again."].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["Share or save a copy"].isEnabled)
  }
}
