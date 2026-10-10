import XCTest

final class PermissionsTests: XCTestCase {
  @MainActor func testPhoneDisplaysHostGrantsWithoutOfferingToExpandThem() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-chats"]
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 5))
    app.buttons["Open chat history"].tap()
    app.buttons["Settings"].tap()
    app.buttons["Permissions"].tap()
    let files = app.descendants(matching: .any)["phone-fileTransfer"]
    XCTAssertTrue(files.waitForExistence(timeout: 5))
    XCTAssertTrue(files.label.contains("Allowed"))
    XCTAssertLessThan(files.frame.height, 120, "A permission row must not expand to fill the form")
    let workspace = app.descendants(matching: .any)["phone-workspaceAdministration"]
    XCTAssertTrue(workspace.label.contains("Not allowed"))
    XCTAssertLessThan(workspace.frame.height, 120)
    app.swipeUp()
    let schedules = app.descendants(matching: .any)["phone-automationManagement"]
    XCTAssertTrue(schedules.label.contains("Not allowed"))
    XCTAssertEqual(app.switches.count, 0)
    XCTAssertTrue(app.staticTexts["Change access in OpenWork on your computer."].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Phone permissions - host grants"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
