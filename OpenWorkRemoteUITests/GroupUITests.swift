import XCTest

@MainActor final class GroupUITests: XCTestCase {
  private func open(_ options: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats", "-groups"] + options
    app.launch()
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout: 15))
    history.tap()
    return app
  }
  func testCreateRenameAndRemoveGroupPreserveTheRecentChat() {
    let app = open()
    let new = app.buttons["groups-new"]
    XCTAssertTrue(new.waitForExistence(timeout: 5))
    new.tap()
    let field = app.textFields["group-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("Fixture new group")
    app.buttons["group-name-save"].tap()
    XCTAssertTrue(app.buttons["groups-manage"].waitForExistence(timeout: 5))
    app.buttons["groups-manage"].tap()
    let group = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "group-edit-grp_remote_")
    ).firstMatch
    XCTAssertTrue(group.waitForExistence(timeout: 5))
    let gid = group.identifier.replacingOccurrences(of: "group-edit-", with: "")
    group.tap()
    let name = app.textFields["group-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17) + "Renamed fixture")
    XCTAssertEqual(name.value as? String, "Renamed fixture")
    app.buttons["group-name-save"].tap()
    XCTAssertTrue(app.buttons["group-remove-" + gid].waitForExistence(timeout: 5))
    app.buttons["group-remove-" + gid].tap()
    app.alerts.buttons["Remove group"].tap()
    XCTAssertTrue(app.buttons["groups-manage-done"].waitForExistence(timeout: 5))
    app.buttons["groups-manage-done"].tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat")).firstMatch
        .exists)
  }
  func testMoveChatUsesExplicitSaveAndLocalCancel() {
    let app = open()
    let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample chat"))
      .firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
    chat.press(forDuration: 1)
    app.buttons["Move to group"].tap()
    XCTAssertTrue(app.buttons["move-chat-save"].waitForExistence(timeout: 5))
    app.buttons["move-group-second"].tap()
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Move chat reviewed native flow"
    capture.lifetime = .keepAlways
    add(capture)
    app.buttons["move-chat-cancel"].tap()
    XCTAssertTrue(app.buttons["groups-new"].exists)
    app.buttons["group-filter-"].tap()
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
    chat.press(forDuration: 1)
    app.buttons["Move to group"].tap()
    app.buttons["move-group-second"].tap()
    app.buttons["move-chat-save"].tap()
    XCTAssertTrue(app.buttons["group-filter-second"].waitForExistence(timeout: 5))
    app.buttons["group-filter-second"].tap()
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
  }
  func testUnsupportedAndSlowReadsKeepGroupsVisibleAndDoneLocal() {
    let blocked = open(["-groups-unsupported"])
    blocked.buttons["groups-manage"].tap()
    XCTAssertTrue(
      blocked.staticTexts[
        "Group controls are unavailable on this computer. Update OpenWork Remote Preview or manage groups on your computer."
      ].waitForExistence(timeout: 5))
    let capture = XCTAttachment(screenshot: blocked.screenshot())
    capture.name = "Group controls unavailable"
    capture.lifetime = .keepAlways
    add(capture)
    blocked.buttons["groups-manage-done"].tap()
    XCTAssertTrue(blocked.buttons["groups-manage"].exists)
    blocked.terminate()
    let slow = open(["-slow-groups"])
    slow.buttons["groups-manage"].tap()
    slow.buttons["groups-manage-done"].tap()
    XCTAssertTrue(slow.buttons["groups-manage"].waitForExistence(timeout: 3))
  }
}
