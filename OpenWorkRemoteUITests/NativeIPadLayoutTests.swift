import XCTest
import UIKit

extension XCUIApplication {
  @MainActor func launchForNativeWindowQualification(){
    launch()
    guard UIDevice.current.userInterfaceIdiom == .pad,
      ProcessInfo.processInfo.environment["POCKETWORK_UI_NARROW_WINDOW"] == "1" else{return}
    guard #available(iOS 26.0,*) else{
      XCTFail("The corner-resize cohort requires iPadOS26 or newer; qualify older Split View separately")
      return
    }
    let window=windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout:5))
    if window.frame.width>=600{
      let corner=window.coordinate(withNormalizedOffset:CGVector(dx:1,dy:1)).withOffset(CGVector(dx:-8,dy:-8))
      corner.press(forDuration:0.2,thenDragTo:window.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.82)))
    }
    XCTAssertLessThan(window.frame.width,600,"The narrow cohort requires an actual iPadOS window")
  }
}

final class NativeIPadLayoutTests:XCTestCase{
  @MainActor func testNarrowWindowKeepsConversationAndSettingsReachable()throws{
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,"Tablet window qualification")
    guard #available(iOS 26.0,*) else{throw XCTSkip("Qualify older iPadOS Split View separately")}
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app"];app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5));app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
    let composer=app.textFields["composer"]
    expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:composer);waitForExpectations(timeout:5)
    let window=app.windows.firstMatch,original=window.frame
    let corner=window.coordinate(withNormalizedOffset:CGVector(dx:1,dy:1)).withOffset(CGVector(dx:-8,dy:-8))
    let target=window.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.82))
    corner.press(forDuration:0.2,thenDragTo:target)
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Actual iPadOS narrow window";proof.lifetime = .keepAlways;add(proof)
    let geometry=XCTAttachment(string:"Original window: \(original); after resize: \(window.frame)");geometry.lifetime = .keepAlways;add(geometry)
    defer{
      let grip=window.coordinate(withNormalizedOffset:CGVector(dx:1,dy:1)).withOffset(CGVector(dx:-8,dy:-8))
      // Reach the screen edge so iPadOS snaps back to the original full window.
      let restored=window.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:original.maxX-window.frame.minX-1,dy:original.maxY-window.frame.minY-1))
      grip.press(forDuration:0.2,thenDragTo:restored)
      expectation(for:NSPredicate{_,_ in window.frame.width>=original.width-1},evaluatedWith:nil)
      waitForExpectations(timeout:5)
      XCTAssertGreaterThanOrEqual(window.frame.width,original.width-1,"Restore the original test window")
    }
    XCTAssertLessThan(window.frame.width,600,"Exercise a real narrow iPadOS app window, not a resized simulator preview")
    XCTAssertTrue(composer.isHittable);XCTAssertTrue(app.buttons["composer-add"].isHittable)
    XCTAssertGreaterThanOrEqual(app.buttons["composer-add"].frame.height,44)
    app.buttons["Model and chat settings"].tap()
    XCTAssertTrue(app.buttons["native-settings-done"].waitForExistence(timeout:4));app.buttons["native-settings-done"].tap()
    XCTAssertTrue(composer.waitForExistence(timeout:3))
  }
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
