import XCTest

final class AboutUITests: XCTestCase {
  @MainActor private func launch(largeText: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-information", "-ui-testing-onboarding"]
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
      app.swipeUp()
    }
  }
  @MainActor func testHelpAndLegalAreAvailableBeforePairing() {
    let app = launch()
    let about = app.buttons["welcome-about"]
    reveal(about, app: app)
    XCTAssertTrue(about.waitForExistence(timeout: 5))
    about.tap()
    XCTAssertEqual(app.staticTexts["about-name"].label, "PocketWork")
    XCTAssertTrue(app.descendants(matching: .any)["about-developer"].label.contains("Salty Panda LLC"))
    XCTAssertTrue(app.buttons["about-support-email"].exists)
    app.buttons["about-help"].tap()
    XCTAssertTrue(app.scrollViews["information-document-help"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Connect your computer"].exists)
    let supportEmail = app.buttons["help-support-email"]
    reveal(supportEmail, app: app)
    XCTAssertTrue(supportEmail.isHittable)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    for id in ["privacy", "terms", "license", "notices"] {
      let row = app.buttons["about-" + id]
      reveal(row, app: app)
      row.tap()
      let document = id == "license" ? "sourceLicense" : id
      XCTAssertTrue(app.scrollViews["information-document-" + document].waitForExistence(timeout: 3))
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }
    app.swipeDown()
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "PocketWork About synthetic unpaired"
    image.lifetime = .keepAlways
    add(image)
  }
  @MainActor func testUnpairedHelpWorksAtLargestDynamicType() {
    let app = launch(largeText: true)
    let about = app.buttons["welcome-about"]
    reveal(about, app: app)
    XCTAssertTrue(about.isHittable)
    about.tap()
    let help = app.buttons["about-help"]
    reveal(help, app: app)
    help.tap()
    XCTAssertTrue(app.scrollViews["information-document-help"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Connect your computer"].exists)
  }
}
