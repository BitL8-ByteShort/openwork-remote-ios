import XCTest
import UIKit

final class NativeIPadLayoutTests:XCTestCase{
  @MainActor func testConversationComposerKeepsAReadableWidthInLandscape()throws{
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,"Tablet layout qualification")
    XCUIDevice.shared.orientation = .portrait
    defer{XCUIDevice.shared.orientation = .portrait}
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app"];app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5));app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.waitForExistence(timeout:4))
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:5))
    XCUIDevice.shared.orientation = .landscapeLeft
    expectation(for:NSPredicate{_,_ in app.frame.width>app.frame.height},evaluatedWith:nil)
    waitForExpectations(timeout:5)
    let add=app.buttons["composer-add"],send=app.buttons["send-message"]
    XCTAssertTrue(add.isHittable && send.exists)
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Full-device iPad landscape conversation";proof.lifetime = .keepAlways;self.add(proof)
    XCTAssertLessThanOrEqual(send.frame.maxX-add.frame.minX,768,"Use the existing readable content width on iPad")
    XCTAssertGreaterThanOrEqual(add.frame.height,44)
  }
}
