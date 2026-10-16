import XCTest

/// Opt-in normal-app checks using explicitly owned native qualification fixtures.
/// Pairing uses the real UI. No fixture launch flags or Keychain injection are used.
final class NativeJoinedInputTests: XCTestCase {
  private struct ReviewerSafariConfiguration:Decodable{
    let disposable:Bool
    let ownerNonce:String
    let origin:URL
    let password:String
  }
  @MainActor func testNormalReleasePasswordPairingThroughReview()throws{
    #if !targetEnvironment(simulator)
    throw XCTSkip("This opt-in flow owns a qualification Simulator.")
    #else
    guard let path=ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_PASSWORD_UI_CONFIG"] else{
      throw XCTSkip("Requires the private, explicitly owned native reviewer configuration.")
    }
    let file=URL(fileURLWithPath:path),bytes=try Data(contentsOf:file)
    guard bytes.count<2_000_000 else{throw XCTSkip("Unexpected qualification fixture size")}
    let config=try JSONDecoder().decode(ReviewerSafariConfiguration.self,from:bytes)
    guard config.disposable,config.ownerNonce.range(of:#"^[0-9a-f]{32}$"#,options:.regularExpression) != nil,
      config.origin.scheme=="https",config.origin.host != nil,config.origin.user==nil,config.origin.password==nil,
      ["","/"].contains(config.origin.path),config.origin.query==nil,config.origin.fragment==nil else{
      throw XCTSkip("Use only the explicitly owned native HTTPS reviewer target")
    }
    let attempt=file.appendingPathExtension("native-password-ui-attempt")
    guard !FileManager.default.fileExists(atPath:attempt.path) else{
      throw XCTSkip("Inspect the existing password-pairing attempt before another native issuance.")
    }
    continueAfterFailure=false
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=[];app.launch()
    let entry:String
    if app.buttons["native-get-started"].waitForExistence(timeout:5){
      entry="welcome"
      app.buttons["native-get-started"].tap();app.buttons["native-computer-ready"].tap()
    }else{
      entry="settings"
      let history=app.buttons["Open chat history"]
      XCTAssertTrue(history.waitForExistence(timeout:25));history.tap()
      let settings=app.buttons["Settings"]
      XCTAssertTrue(settings.waitForExistence(timeout:5));settings.tap()
      let pairAgain=app.buttons["native-pair-again"]
      XCTAssertTrue(pairAgain.waitForExistence(timeout:5))
      for _ in 0..<8{if pairAgain.isHittable{break};app.swipeUp()}
      XCTAssertTrue(pairAgain.isHittable);pairAgain.tap()
    }
    let option=app.buttons["native-server-password"]
    for _ in 0..<8{if option.isHittable{break};app.swipeUp()}
    XCTAssertTrue(option.isHittable);option.tap()
    let address=app.textFields["native-server-address"],password=app.secureTextFields["native-server-password-value"]
    XCTAssertTrue(address.waitForExistence(timeout:5));address.tap();address.typeText(config.origin.absoluteString+"\n")
    password.typeText(config.password)
    app.buttons["native-review-server-password"].tap()
    let reviewed=app.staticTexts["native-password-reviewed-origin"]
    XCTAssertTrue(reviewed.waitForExistence(timeout:5));XCTAssertEqual(reviewed.label,config.origin.absoluteString)
    let alert=app.alerts["Save Password?"],sheet=app.sheets["Save Password?"]
    let save:XCUIElement? = alert.waitForExistence(timeout:2) ? alert : (sheet.waitForExistence(timeout:2) ? sheet:nil)
    if let save{
      let decline=save.buttons["Not Now"],actions=save.scrollViews.containing(.button,identifier:"Not Now").firstMatch
      for _ in 0..<3{if decline.isHittable{break};if actions.exists{actions.swipeUp()}}
      XCTAssertTrue(decline.isHittable);decline.tap()
    }
    let connect=app.buttons["native-confirm-server-password"]
    if !connect.isHittable{app.swipeUp()};XCTAssertTrue(connect.isHittable)
    try Data("One explicit native HTTPS password-pairing attempt through normal Release UI.\n".utf8).write(to:attempt,options:.atomic)
    connect.tap()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:60))
    XCTAssertFalse(app.secureTextFields["native-server-password-value"].exists)
    app.terminate();app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:40),"Reload the ordinary paired credential without the server password")
    let result:[String:String]=["entry":entry,"nativePasswordPairing":"passed","savedPairedCredentialReload":"passed","providerExecution":"none"]
    try JSONSerialization.data(withJSONObject:result,options:.sortedKeys).write(to:file.appendingPathExtension("native-password-ui-result.json"),options:.atomic)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Normal Release native password connection restored";proof.lifetime = .keepAlways;add(proof)
    app.terminate()
    #endif
  }
  @MainActor func testNativeSafariReviewerPasswordSignIn()throws{
    #if !targetEnvironment(simulator)
    throw XCTSkip("This opt-in sign-in owns the clean reviewer Simulator.")
    #else
    guard let path=ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_REVIEW_SAFARI_CONFIG"] else{
      throw XCTSkip("Requires privately preflight-verified isolated native reviewer credentials.")
    }
    let config=try JSONDecoder().decode(ReviewerSafariConfiguration.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    guard config.disposable,config.ownerNonce.range(of:#"^[0-9a-f]{32}$"#,options:.regularExpression) != nil,
      config.origin.scheme=="https",let host=config.origin.host,host.hasSuffix(".opentunnel.xyz"),
      config.origin.user==nil,config.origin.password==nil,config.origin.query==nil,config.origin.fragment==nil,
      config.password.utf8.count>=16,config.password.utf8.count<=512 else{
      throw XCTSkip("The supplied credentials are not the dedicated isolated reviewer fixture.")
    }
    continueAfterFailure=false
    let safari=XCUIApplication(bundleIdentifier:"com.apple.mobilesafari");safari.launchArguments=[];safari.launch()
    let bar=safari.textFields["TabBarItemTitle"]
    XCTAssertTrue(bar.waitForExistence(timeout:15))
    bar.tap()
    let address=safari.textFields["URL"]
    XCTAssertTrue(address.waitForExistence(timeout:10))
    let clear=safari.buttons["Clear text"]
    if clear.exists{clear.tap()}
    address.typeText(config.origin.absoluteString)
    XCTAssertEqual(address.value as? String,config.origin.absoluteString,"Verify the complete address before navigation")
    // Hardware-keyboard capture can put Safari's on-screen Go key offscreen.
    // Submit through the focused native field after verifying its full value.
    address.typeText("\n")
    let usePassword=safari.webViews.buttons["Use password"]
    XCTAssertTrue(usePassword.waitForExistence(timeout:60),"Wait for the actual native sign-in page after navigation")
    usePassword.tap()
    let server=safari.webViews.textFields.firstMatch
    let password=safari.webViews.secureTextFields.firstMatch
    XCTAssertTrue(server.waitForExistence(timeout:15));XCTAssertTrue(password.waitForExistence(timeout:15))
    let destination=URL(string:server.value as? String ?? "")
    XCTAssertTrue(destination?.scheme==config.origin.scheme && destination?.host==host && destination?.port==config.origin.port,"Verify the password destination before typing")
    password.tap();password.typeText(config.password)
    let connect=safari.webViews.buttons["Connect"]
    XCTAssertTrue(connect.isEnabled);connect.tap()
    let savePassword=safari.alerts["Save Password?"]
    if savePassword.waitForExistence(timeout:5){savePassword.buttons["Not Now"].tap()}
    XCTAssertTrue(safari.webViews.textFields["Search sessions"].waitForExistence(timeout:60),"Require an authenticated native project/history shell")
    let ownedHistory=safari.webViews.otherElements.matching(NSPredicate(format:"label CONTAINS %@","PocketWork review starter — local model")).firstMatch
    XCTAssertTrue(ownedHistory.waitForExistence(timeout:15),"Require actual synthetic history, not just a loaded public page")
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Fresh native Safari reviewer password sign-in";proof.lifetime = .keepAlways;add(proof)
    #endif
  }
  private struct ReviewerConfiguration:Decodable{
    let disposable:Bool
    let ownerNonce:String
    let projectID:String
    let projectName:String
    let chatTitle:String
  }
  @MainActor func testNormalReleaseIsolatedReviewerReply()throws{
    #if !targetEnvironment(simulator)
    throw XCTSkip("This opt-in journey owns a clean Simulator and an isolated review server.")
    #else
    guard let path=ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_REVIEW_UI_CONFIG"] else{
      throw XCTSkip("Requires a preflight-verified, isolated reviewer project and a normally paired app.")
    }
    let file=URL(fileURLWithPath:path)
    let config=try JSONDecoder().decode(ReviewerConfiguration.self,from:Data(contentsOf:file))
    guard config.disposable,config.ownerNonce.range(of:#"^[0-9a-f]{32}$"#,options:.regularExpression) != nil,
      config.projectID.range(of:#"^[0-9a-f]{40}$"#,options:.regularExpression) != nil,
      config.projectName=="PocketWork Review",config.chatTitle=="PocketWork review starter — local model" else{
      throw XCTSkip("The supplied target is not the dedicated synthetic reviewer environment.")
    }
    let attempted=file.appendingPathExtension("send-attempt")
    guard !FileManager.default.fileExists(atPath:attempted.path) else{
      throw XCTSkip("Read the owned native history/inbox before authorizing another send. Never replay an unknown outcome.")
    }
    continueAfterFailure=false
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=[];app.launch()
    let history=app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout:30));history.tap()
    let project=app.buttons["native-project-"+config.projectID]
    XCTAssertTrue(project.waitForExistence(timeout:60),"Wait for the actual native project response, not just the connected shell");project.tap()
    let list=app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout:5))
    let chat=app.buttons.containing(.staticText,identifier:config.chatTitle).firstMatch
    for _ in 0..<16{if chat.exists && chat.isHittable{break};list.swipeUp()}
    XCTAssertTrue(chat.waitForExistence(timeout:20));XCTAssertTrue(chat.isHittable);chat.tap()
    let composer=app.textFields["composer"],send=app.buttons["send-message"]
    XCTAssertTrue(composer.waitForExistence(timeout:15));XCTAssertTrue(composer.isEnabled)
    XCTAssertTrue(["","Message OpenCode"].contains(composer.value as? String ?? "unexpected"),"Preserve an existing draft")
    XCTAssertFalse(send.isEnabled,"Do not add a request to another pending selection")
    composer.tap();composer.typeText("Reply with exactly: PocketWork mobile review ready")
    XCTAssertTrue(send.isEnabled)
    try Data("One explicitly authorized synthetic reviewer prompt; inspect history/inbox before any later attempt.\n".utf8).write(to:attempted,options:.atomic)
    send.tap()
    let allow=app.buttons["sharing-review-allow"]
    if allow.waitForExistence(timeout:20){
      XCTAssertTrue(allow.isHittable);allow.tap()
      XCTAssertTrue(send.waitForExistence(timeout:10));XCTAssertTrue(send.isEnabled)
      send.tap()
    }
    XCTAssertTrue(app.staticTexts["PocketWork mobile review ready"].waitForExistence(timeout:120))
    XCTAssertFalse(app.staticTexts["This chat could not be loaded. Reconnect or try opening it again."].exists)
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Normal Release isolated reviewer reply";proof.lifetime = .keepAlways;add(proof)
    app.terminate()
    #endif
  }
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
    let list=app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout:5))
    // Recent chats follow the project list; lazy rows do not exist until scrolled in.
    for _ in 0..<20{if chat.exists && chat.isHittable{break};list.swipeUp()}
    XCTAssertTrue(chat.waitForExistence(timeout:15))
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
