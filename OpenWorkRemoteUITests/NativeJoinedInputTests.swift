import XCTest

/// Opt-in local draft check against an already paired, disposable native chat.
/// No fixture launch flags, credential injection or server writes are used.
final class NativeJoinedInputTests: XCTestCase {
  @MainActor func testNormalAppTypingPersistsAcrossRelaunchAndCanBeCleared() throws {
    guard let project = ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_INPUT_PROJECT"] else {
      throw XCTSkip("Requires the selected owned native qualification chat.")
    }
    guard project.range(of: #"^PocketWork Native (Mac|NUC) \+ 日本語 [0-9a-f]{8}$"#, options: .regularExpression) != nil else {
      throw XCTSkip("The project must be an owned native qualification fixture.")
    }
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = []
    app.launch()
    let summary = app.buttons["Model and chat settings"]
    XCTAssertTrue(summary.waitForExistence(timeout: 30))
    expectation(for: NSPredicate(format: "value CONTAINS %@", project), evaluatedWith: summary)
    waitForExpectations(timeout: 30)
    let composer = app.textFields["composer"]
    XCTAssertTrue(composer.waitForExistence(timeout: 10))
    XCTAssertTrue(composer.isEnabled)
    XCTAssertTrue(["", "Message OpenCode"].contains(composer.value as? String ?? "unexpected"), "Preserve any existing unsent text")
    XCTAssertFalse(app.buttons["send-message"].isEnabled, "Do not run with another pending selection")
    let marker = "PocketWork native keyboard qualification."
    composer.tap()
    composer.typeText(marker)
    XCTAssertEqual(composer.value as? String, marker)
    XCTAssertTrue(app.buttons["send-message"].isEnabled, "Typing must update the actual draft binding")
    app.terminate()
    app.launch()
    XCTAssertTrue(composer.waitForExistence(timeout: 30))
    expectation(for: NSPredicate(format: "value CONTAINS %@", project), evaluatedWith: summary)
    waitForExpectations(timeout: 30)
    XCTAssertEqual(composer.value as? String, marker, "The normal app must restore its durable draft")
    composer.tap()
    composer.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: marker.count))
    XCTAssertTrue(["", "Message OpenCode"].contains(composer.value as? String ?? "unexpected"))
    XCTAssertFalse(app.buttons["send-message"].isEnabled)
    let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    proof.name = "Normal native app after typing, relaunch and draft clearing"
    proof.lifetime = .keepAlways
    add(proof)
  }
}
