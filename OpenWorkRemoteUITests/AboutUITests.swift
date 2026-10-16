import XCTest

final class AboutUITests: XCTestCase {
  @MainActor private func launch(largeText: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-native-startup"]
    if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
    app.launch()
    return app
  }
  @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<12 {
      if element.exists && element.isHittable {
        // A List row can become hittable before an accessibility-size scroll stops.
        // Wait for its frame to settle so the test taps the position it observed.
        var frame = element.frame
        var unchangedSince = Date()
        let settled = NSPredicate { _, _ in
          let current = element.frame
          if current != frame {
            frame = current
            unchangedSince = Date()
          }
          return element.isHittable && Date().timeIntervalSince(unchangedSince) >= 0.3
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: element)], timeout: 4), .completed)
        return
      }
      // On iPad the document is a centered sheet. A whole-app swipe can
      // land on the welcome screen behind it instead of scrolling its text.
      let help = app.scrollViews["information-document-help"]
      if help.exists { help.swipeUp() }
      else if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
      else { app.windows.firstMatch.swipeUp() }
    }
  }
  @MainActor func testHelpAndLegalAreAvailableBeforePairing() {
    let app = launch()
    let about = app.buttons["native-about-open"]
    reveal(about, app: app)
    XCTAssertTrue(about.waitForExistence(timeout: 5))
    about.tap()
    XCTAssertEqual(app.staticTexts["about-name"].label, "PocketWork")
    XCTAssertTrue(app.descendants(matching: .any)["about-developer"].label.contains("Salty Panda LLC"))
    let help=app.buttons["about-help"]
    reveal(help,app:app)
    XCTAssertTrue(help.isHittable);help.tap()
    XCTAssertTrue(app.scrollViews["information-document-help"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Connect OpenCode v2"].exists)
    // SwiftUI Link is exposed as Link on iPad and Button on some phone OSes.
    let supportEmail = app.descendants(matching: .any)["help-support-email"]
    reveal(supportEmail, app: app)
    XCTAssertTrue(supportEmail.isHittable)
    // The native welcome and its About sheet have separate navigation stacks.
    // Scope Back to the visible document instead of the underlying welcome bar.
    app.navigationBars["Help"].buttons["BackButton"].tap()
    XCTAssertTrue(app.buttons["about-help"].waitForExistence(timeout: 3))
    let contact = app.descendants(matching: .any)["about-support-email"]
    reveal(contact, app: app)
    XCTAssertTrue(contact.isHittable)
    for (id, title) in [("privacy", "Privacy policy"), ("terms", "Terms of use"),
      ("license", "Source license"), ("notices", "Open-source notices")] {
      let row = app.buttons["about-" + id]
      reveal(row, app: app)
      row.tap()
      let document = id == "license" ? "sourceLicense" : id
      XCTAssertTrue(app.scrollViews["information-document-" + document].waitForExistence(timeout: 3))
      app.navigationBars[title].buttons["BackButton"].tap()
      XCTAssertTrue(app.buttons["about-help"].waitForExistence(timeout: 3))
    }
    app.swipeDown()
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "PocketWork About synthetic unpaired"
    image.lifetime = .keepAlways
    add(image)
  }
  @MainActor func testUnpairedHelpWorksAtLargestDynamicType() {
    let app = launch(largeText: true)
    let about = app.buttons["native-about-open"]
    reveal(about, app: app)
    XCTAssertTrue(about.isHittable)
    about.tap()
    let help = app.buttons["about-help"]
    reveal(help, app: app)
    help.tap()
    XCTAssertTrue(app.scrollViews["information-document-help"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Connect OpenCode v2"].exists)
  }
}
