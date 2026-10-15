import XCTest

final class NativeAccessibilityTests:XCTestCase{
  @MainActor private func audit(_ app:XCUIApplication)throws{
    // Full contrast/predictive-clipping audit results are recorded separately.
    // This structural subset does not clear those findings or physical VoiceOver.
    try app.performAccessibilityAudit(for:[.elementDetection,.sufficientElementDescription,.hitRegion,.trait]){issue in
      print("Native accessibility issue: \(issue.compactDescription); \(issue.element?.debugDescription ?? "no element"); \(issue.detailedDescription)")
      return false
    }
  }
  @MainActor func testLargestTextNativeWelcomeStructuralAccessibility()throws{
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-startup","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launchForNativeWindowQualification()
    XCTAssertTrue(app.buttons["native-get-started"].waitForExistence(timeout:5))
    try audit(app)
  }
  @MainActor func testLargestTextNativeConversationAndRequiredInputStructuralAccessibility()throws{
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launchForNativeWindowQualification()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5));app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout:4))
    for _ in 0..<8{if row.exists && row.isHittable{break};app.collectionViews.firstMatch.swipeUp()}
    XCTAssertTrue(row.exists && row.isHittable);row.tap()
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:4))
    XCTAssertTrue(app.buttons["native-approval-open"].exists)
    try audit(app)
  }
  @MainActor func testLargestTextConversationKeepsRequiredInputsAndComposerReachable(){
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launchForNativeWindowQualification()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5));app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout:4))
    for _ in 0..<8{if row.exists && row.isHittable{break};app.collectionViews.firstMatch.swipeUp()}
    XCTAssertTrue(row.exists && row.isHittable)
    row.tap()
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:5))
    XCTAssertTrue(app.buttons["native-form-open"].isHittable)
    XCTAssertTrue(app.buttons["native-approval-open"].isHittable)
    XCTAssertTrue(app.buttons["composer-add"].isHittable)
    XCTAssertGreaterThanOrEqual(app.buttons["composer-add"].frame.height,44)
    XCTAssertGreaterThanOrEqual(app.scrollViews["chat-conversation"].frame.height,app.frame.height>=800 ? 150:64)
    XCTAssertGreaterThanOrEqual(app.buttons["Model and chat settings"].frame.minY,0)
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Native conversation largest text";proof.lifetime = .keepAlways;add(proof)
    app.buttons["native-form-open"].tap()
    XCTAssertTrue(app.buttons["native-form-close"].waitForExistence(timeout:4));app.buttons["native-form-close"].tap()
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:3))
  }
  @MainActor func testLargestTextKeyboardKeepsNavigationAndRequiredInputsReachable(){
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launchForNativeWindowQualification()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5));app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(app.navigationBars["Your chats"].waitForExistence(timeout:4))
    for _ in 0..<8{if row.exists && row.isHittable{break};app.collectionViews.firstMatch.swipeUp()}
    XCTAssertTrue(row.exists && row.isHittable);row.tap()
    let composer=app.textFields["composer"];XCTAssertTrue(composer.waitForExistence(timeout:4));composer.tap();composer.typeText("Keyboard draft")
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:3))
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Largest text conversation with keyboard";proof.lifetime = .keepAlways;add(proof)
    XCTAssertGreaterThanOrEqual(app.buttons["Model and chat settings"].frame.minY,app.frame.minY)
    XCTAssertTrue(app.buttons["Open chat history"].isHittable)
    XCTAssertTrue(app.buttons["native-approval-open"].isHittable)
    XCTAssertTrue(app.buttons["native-form-open"].isHittable)
    XCTAssertTrue(app.buttons["composer-add"].isHittable)
    app.buttons["native-form-open"].tap()
    XCTAssertTrue(app.buttons["native-form-close"].waitForExistence(timeout:4));app.buttons["native-form-close"].tap()
    XCTAssertEqual(composer.value as? String,"Keyboard draft")
  }
}
