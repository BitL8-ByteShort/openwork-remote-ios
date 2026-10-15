import XCTest

/// Opt-in normal-app checks using explicitly owned native qualification fixtures.
/// Pairing uses the real UI. No fixture launch flags or Keychain injection are used.
final class NativeJoinedInputTests: XCTestCase {
  private struct PhotoConfiguration:Decodable{
    let disposable:Bool
    let pairing:String
    let projectID:String
    let projectName:String
    let chatTitle:String
  }
  private func photoConfiguration() throws -> (PhotoConfiguration,URL){
    #if !targetEnvironment(simulator)
    throw XCTSkip("This opt-in check owns a clean Simulator, not a physical device.")
    #else
    guard let path=ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_PHOTO_UI_CONFIG"] else{
      throw XCTSkip("Requires a fresh native pairing and an owned disposable chat/photo fixture.")
    }
    let file=URL(fileURLWithPath:path)
    let config=try JSONDecoder().decode(PhotoConfiguration.self,from:Data(contentsOf:file))
    guard config.disposable,
      config.projectName.range(of:#"^PocketWork Native (Mac|NUC) \+ 日本語 [0-9a-f]{8}$"#,options:.regularExpression) != nil,
      config.chatTitle.range(of:#"^PocketWork photo check [0-9a-f]{8}$"#,options:.regularExpression) != nil else{
      throw XCTSkip("The supplied fixture is not an owned native qualification target.")
    }
    return(config,file)
    #endif
  }
  @MainActor func testNormalReleasePairingThroughReview() throws{
    let(config,file)=try photoConfiguration()
    let attempted=file.appendingPathExtension("pairing-attempt")
    guard !FileManager.default.fileExists(atPath:attempted.path) else{
      throw XCTSkip("This pairing was already attempted. Inspect saved connection/readback instead of redeeming again.")
    }
    continueAfterFailure=false
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=[];app.launch()
    XCTAssertTrue(app.buttons["native-get-started"].waitForExistence(timeout:15),"Use the explicitly clean qualification Simulator")
    app.buttons["native-get-started"].tap();app.buttons["native-computer-ready"].tap()
    app.buttons["native-paste-pairing"].tap()
    let field=app.textViews["native-pairing-payload"]
    XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText(config.pairing)
    app.buttons["native-review-payload"].tap()
    XCTAssertTrue(app.staticTexts["native-reviewed-origin"].waitForExistence(timeout:5))
    try Data("Fresh native code submitted once through the normal UI.\n".utf8).write(to:attempted,options:.atomic)
    app.buttons["native-confirm-connection"].tap()
    let history=app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout:40))
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Normal Release native pairing through explicit review";proof.lifetime = .keepAlways;add(proof)
    app.terminate()
  }
  @MainActor func testNormalReleaseSystemPhotoSelection() throws{
    let(config,_)=try photoConfiguration()
    continueAfterFailure=false
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=[];app.launch()
    let history=app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout:30));history.tap()
    let project=app.buttons["native-project-"+config.projectID]
    for _ in 0..<16{if project.exists && project.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(project.exists);XCTAssertTrue(project.isHittable);project.tap()
    let chat=app.buttons.containing(.staticText,identifier:config.chatTitle).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout:15))
    for _ in 0..<12{if chat.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(chat.isHittable);chat.tap()
    let composer=app.textFields["composer"]
    XCTAssertTrue(composer.waitForExistence(timeout:10));XCTAssertTrue(composer.isEnabled)
    app.buttons["composer-add"].tap();app.buttons["Photos"].tap()
    let photoButtons=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Photo,"))
    let photoImages=app.images.matching(NSPredicate(format:"label BEGINSWITH %@","Photo,"))
    // The clean Simulator contains only seeded/default synthetic media, never personal photos.
    let photo=photoButtons.firstMatch.waitForExistence(timeout:10) ? photoButtons.firstMatch:photoImages.firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout:10));photo.tap()
    let allow=app.buttons["sharing-review-allow"]
    XCTAssertTrue(allow.waitForExistence(timeout:20));XCTAssertTrue(allow.isHittable);allow.tap()
    let chip=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-attachment-chip-")).firstMatch
    XCTAssertTrue(chip.waitForExistence(timeout:10))
    expectation(for:NSPredicate(format:"value == %@","Ready"),evaluatedWith:chip)
    waitForExpectations(timeout:30)
    XCTAssertFalse(app.buttons["native-attachment-done"].exists,"Selection returns directly to the draft")
    XCTAssertTrue(["","Message OpenCode"].contains(composer.value as? String ?? "unexpected"))
    XCTAssertTrue(app.buttons["send-message"].isEnabled,"Ready photo supports an explicit file-only Send")
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Normal Release system photo selection ready in draft";proof.lifetime = .keepAlways;add(proof)
    // Do not send a model request: this check owns pairing and selection/preparation only.
    app.terminate()
  }
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
