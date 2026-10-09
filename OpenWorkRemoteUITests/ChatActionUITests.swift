import XCTest

@MainActor final class ChatActionUITests: XCTestCase {
  private func open(_ options: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats", "-chat-actions"] + options
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 15))
    app.buttons["Open chat history"].tap()
    return app
  }
  private func action(_ label: String, in app: XCUIApplication, title: String = "Sample chat") {
    let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
    chat.press(forDuration: 1)
    app.buttons[label].tap()
    XCTAssertTrue(app.buttons["chat-action-cancel"].waitForExistence(timeout: 5))
  }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
  func testCancelDoesNotCreateOrDeleteAndSlowCheckStillDismisses() {
    let app = open(["-slow-chat-actions"])
    action("Delete chat", in: app)
    XCTAssertTrue(app.buttons["chat-action-cancel"].isEnabled)
    app.buttons["chat-action-cancel"].tap()
    XCTAssertTrue(app.buttons["groups-manage"].waitForExistence(timeout: 3))
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch
        .exists)
  }
  func testWholeForkOpensANewChatAndPreservesTheParent() {
    let app = open()
    action("Continue in a new chat", in: app)
    let confirm = app.buttons["chat-action-confirm"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    XCTAssertTrue(confirm.isEnabled)
    capture("Continue in a new chat", app)
    confirm.tap()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 5))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Copy of Sample chat"))
        .firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label == %@", "Sample chat")).firstMatch.exists)
  }
  func testDeleteRequiresConfirmationAndLeavesOtherChats() {
    let app = open()
    action("Continue in a new chat", in: app)
    app.buttons["chat-action-confirm"].tap()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 5))
    app.buttons["Open chat history"].tap()
    action("Delete chat", in: app, title: "Copy of Sample chat")
    XCTAssertTrue(
      app.staticTexts[
        "This permanently removes this chat and its history from OpenWork on your computer. It cannot be undone here."
      ].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Delete “Copy of Sample chat”?"].exists)
    capture("Permanent chat deletion", app)
    app.buttons["chat-action-confirm"].tap()
    XCTAssertTrue(app.buttons["groups-manage"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch
        .exists)
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Copy of Sample chat"))
        .firstMatch.exists)
  }
  func testLinkedAndRunningChatsRequireComputerHandoff() {
    for option in ["-chat-action-linked", "-chat-action-running"] {
      let app = open([option])
      action("Delete chat", in: app)
      let confirm = app.buttons["chat-action-confirm"]
      XCTAssertTrue(confirm.waitForExistence(timeout: 5))
      XCTAssertFalse(confirm.isEnabled)
      if option == "-chat-action-linked" {
        XCTAssertTrue(app.staticTexts["chat-action-linked"].exists)
        capture("Linked chats block deletion", app)
      }
      app.buttons["chat-action-cancel"].tap()
      app.terminate()
    }
  }
  func testLostForkNeverCreatesAnotherCopyAfterRefresh() {
    let app = open(["-chat-action-lost"])
    action("Continue in a new chat", in: app)
    app.buttons["chat-action-confirm"].tap()
    XCTAssertTrue(app.buttons["chat-action-review"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["chat-action-confirm"].exists)
    app.buttons["chat-action-review"].tap()
    XCTAssertTrue(app.buttons["chat-action-keep-current"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Copy of Sample chat"].exists)
    capture("Uncertain fork reviewed without retry", app)
    app.buttons["chat-action-cancel"].tap()
    let copies = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Copy of Sample chat"))
    XCTAssertEqual(copies.count, 1)
  }
  func testMessageForkUsesAnExplicitExclusiveBoundary() {
    let app = open()
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch.tap()
    let last = app.staticTexts["Last synthetic response"]
    XCTAssertTrue(last.waitForExistence(timeout: 5))
    last.press(forDuration: 1)
    app.buttons["Fork before this message"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(
          format: "label BEGINSWITH %@", "Create a new chat with the messages before this one.")
      ).firstMatch.waitForExistence(timeout: 5))
    app.buttons["chat-action-cancel"].tap()
    XCTAssertTrue(last.waitForExistence(timeout: 3))
  }
}
