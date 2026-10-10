import XCTest

@MainActor final class ChangesUITests: XCTestCase {
  private func open(_ options: [String] = []) -> XCUIApplication {
    let app=XCUIApplication();app.launchArguments=["-ui-testing-chats","-changes"]+options;app.launch()
    let history=app.buttons["Open chat history"];XCTAssertTrue(history.waitForExistence(timeout:15));history.tap()
    let chat=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Sample chat")).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout:5));chat.tap()
    let settings=app.buttons["Model and chat settings"];XCTAssertTrue(settings.waitForExistence(timeout:5));settings.tap()
    let changes=app.buttons["workspace-changes-settings"];XCTAssertTrue(changes.waitForExistence(timeout:5));changes.tap()
    return app
  }
  func testWorkspaceProvenanceAndPassiveDiffAppearOnlyAfterSelection() {
    let app=open(),row=app.buttons["change-row-chg_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    XCTAssertTrue(row.waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["changes-provenance"].exists)
    XCTAssertFalse(app.staticTexts["diff-line-4"].exists);row.tap()
    XCTAssertTrue(app.staticTexts["diff-line-4"].waitForExistence(timeout:5))
    XCTAssertEqual(app.staticTexts["diff-line-4"].label,"Added line: +after")
    XCTAssertFalse(app.buttons["Revert"].exists);XCTAssertFalse(app.buttons["Apply"].exists)
    let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Workspace diff native preview";capture.lifetime = .keepAlways;add(capture)
  }
  func testDeniedGrantRemainsVisibleAndDoneDismisses() {
    let app=open(["-attachment-denied"])
    XCTAssertTrue(app.staticTexts["File access is not allowed for this phone. Allow file transfer in Remote access on your computer."].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["change-row-chg_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].exists)
    let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Workspace changes file access blocked";capture.lifetime = .keepAlways;add(capture)
    app.buttons["changes-done"].tap();XCTAssertTrue(app.buttons["workspace-changes-settings"].waitForExistence(timeout:3))
  }
  func testStaleDiffRequiresRefreshAndSlowReadingDoesNotBlockDone() {
    let app=open(["-change-stale"]),row=app.buttons["change-row-chg_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
    XCTAssertTrue(app.staticTexts["The workspace changed. Refresh changes before opening another file."].waitForExistence(timeout:5))
    app.buttons["diff-refresh"].tap()
    XCTAssertTrue(app.buttons["changes-refresh"].isHittable)
    app.terminate()
    let slow=open(["-slow-changes"]);XCTAssertTrue(slow.buttons["changes-done"].waitForExistence(timeout:3))
    slow.buttons["changes-done"].tap();XCTAssertTrue(slow.buttons["workspace-changes-settings"].waitForExistence(timeout:3))
  }
  func testBinaryAndOmittedLargeDiffsUseComputerHandoffs() {
    let binary=open(["-change-binary"]),row=binary.buttons["change-row-chg_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
    XCTAssertTrue(binary.staticTexts["Binary file. Review this change on your computer."].waitForExistence(timeout:5));binary.terminate()
    let large=open(["-change-large"]),largeRow=large.buttons["change-row-chg_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    XCTAssertTrue(largeRow.waitForExistence(timeout:5));largeRow.tap()
    XCTAssertTrue(large.staticTexts["diff-line-0"].waitForExistence(timeout:5))
    XCTAssertFalse(large.staticTexts["diff-line-200"].exists)
    XCTAssertTrue(large.buttons["Next lines"].isHittable);large.buttons["Next lines"].tap()
    XCTAssertTrue(large.staticTexts["diff-line-200"].waitForExistence(timeout:3))
    XCTAssertFalse(large.staticTexts["diff-line-0"].exists)
    large.buttons["Previous lines"].tap();XCTAssertTrue(large.staticTexts["diff-line-0"].waitForExistence(timeout:3))
  }
}
