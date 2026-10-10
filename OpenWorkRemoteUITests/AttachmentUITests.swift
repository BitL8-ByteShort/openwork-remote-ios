import XCTest

@MainActor final class AttachmentUITests: XCTestCase {
  private func open(_ arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication(); app.launchArguments = ["-ui-testing-chats","-attachment-fixture-files"] + arguments; app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:15)); app.buttons["Open chat history"].tap()
    let chat = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Sample chat")).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout:5)); chat.tap()
    let attachments = app.buttons["composer-add"]
    XCTAssertTrue(attachments.waitForExistence(timeout:5)); attachments.tap(); app.buttons["Photos or files"].tap()
    return app
  }
  func testUnavailableHostShowsComputerInstructionsAndDoneDismissesImmediately() {
    let app = XCUIApplication(); app.launchArguments = ["-ui-testing-chats"]; app.launch()
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout:15)); history.tap()
    let chat = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Sample chat")).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout:5)); chat.tap()
    let attachments = app.buttons["composer-add"]
    XCTAssertTrue(attachments.waitForExistence(timeout:5)); attachments.tap(); app.buttons["Photos or files"].tap()
    XCTAssertTrue(app.staticTexts["This computer does not support attachments yet. Update OpenWork Remote on your computer."].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["Choose photos"].isEnabled)
    let done = app.buttons["attachment-done"]; XCTAssertTrue(done.exists); done.tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
  }
  func testDeniedFileGrantCannotChooseFiles() {
    let app = open(["-attachments","-attachment-denied"])
    XCTAssertTrue(app.staticTexts["File access is not allowed for this phone. Allow file transfer in Remote access on your computer."].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["Choose photos"].isEnabled); XCTAssertFalse(app.buttons["Browse files"].isEnabled)
  }
  func testSelectedPhotoAndPDFOnlySendWhenUserPressesSend() {
    let app = open(["-attachments"])
    let pdf = app.buttons["Use fixture PDF"], photo = app.buttons["Use fixture photo"]
    XCTAssertTrue(pdf.waitForExistence(timeout:5)); pdf.tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Ready to send")).firstMatch.waitForExistence(timeout:5))
    photo.tap()
    XCTAssertTrue(app.staticTexts["Photo.png"].waitForExistence(timeout:5))
    XCTAssertFalse(app.staticTexts["Fixture attachment prompt accepted once."].exists)
    app.buttons["attachment-done"].tap()
    let send = app.buttons["send-message"]; XCTAssertTrue(send.waitForExistence(timeout:3)); XCTAssertTrue(send.isEnabled)
    send.tap()
    XCTAssertTrue(app.staticTexts["Fixture attachment prompt accepted once."].waitForExistence(timeout:5))
    XCTAssertFalse(send.isEnabled)
  }
  func testUncertainCommitOffersStatusCheckAndRemovalInsteadOfRetry() {
    let app = open(["-attachments","-attachment-lost-commit"])
    let pdf = app.buttons["Use fixture PDF"]; XCTAssertTrue(pdf.waitForExistence(timeout:5)); pdf.tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Status unconfirmed")).firstMatch.waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["Retry"].exists)
    app.buttons["Check status"].tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Ready to send")).firstMatch.waitForExistence(timeout:5))
    app.buttons["Remove"].tap()
    XCTAssertFalse(app.staticTexts["fixture.pdf"].exists)
  }
}
