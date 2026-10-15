import XCTest
import CryptoKit

final class NativeAppTests:XCTestCase {
  @MainActor func testLongReplyHasBoundedPagesAndNavigationDoesNotWaitForModelNetwork(){
    checkLongReply()
  }
  @MainActor func testLargestTextLongReplyPagingKeepsLocalNavigationAvailable(){
    checkLongReply(largest:true)
  }
  @MainActor private func checkLongReply(largest:Bool=false){
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app","-native-fixture-long-reply","-slow-native-app-settings"]+(largest ? ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]:[]);app.launchForNativeWindowQualification()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5))
    app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    for _ in 0..<8{if row.exists && row.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
    let open=app.buttons["long-reply-open"]
    for _ in 0..<6{if open.isHittable{break};app.scrollViews["chat-conversation"].swipeDown()}
    XCTAssertTrue(open.waitForExistence(timeout:5));XCTAssertTrue(open.isHittable);open.tap()
    XCTAssertTrue(app.navigationBars["Long reply"].waitForExistence(timeout:4))
    let next=app.buttons["long-reply-next"],back=app.buttons["long-reply-previous"]
    XCTAssertTrue(next.isHittable);XCTAssertGreaterThanOrEqual(next.frame.height,44);next.tap()
    XCTAssertTrue(app.staticTexts["long-reply-position"].label.hasPrefix("Page 2 of "))
    XCTAssertTrue(back.isEnabled);XCTAssertTrue(back.isHittable);back.tap()
    XCTAssertTrue(app.staticTexts["long-reply-position"].label.hasPrefix("Page 1 of "))
    let readerProof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());readerProof.name="Bounded long reply reader";readerProof.lifetime = .keepAlways;add(readerProof)
    app.buttons["long-reply-done"].tap()
    app.buttons["Model and chat settings"].tap()
    let done=app.buttons["native-settings-done"]
    XCTAssertTrue(done.waitForExistence(timeout:4))
    let start=ContinuousClock.now;done.tap()
    // waitForExistence polls after roughly one second even if already present;
    // it must not be included in the local dismissal timing measurement.
    XCTAssertTrue(app.buttons["Open chat history"].exists)
    let elapsed=start.duration(to:.now)
    XCTAssertLessThan(elapsed,.seconds(2),"Local Done must not await the 30-second model request")
    let timing=XCTAttachment(string:"XCUITest tap + immediate visible-element query: \(elapsed). Includes automation/animation; not physical tap-to-pixel latency.")
    timing.name="Local dismissal automation timing";timing.lifetime = .keepAlways;add(timing)
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Bounded native long reply and local navigation";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testCodeBlockScrollsVerticallyToItsFinalLines(){
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app","-native-fixture-code-reply"];app.launchForNativeWindowQualification()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5));app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
    let scroll=app.scrollViews["code-block-scroll"]
    XCTAssertTrue(scroll.waitForExistence(timeout:5))
    let content=app.staticTexts["code-block-content"];let originalY=content.frame.minY
    for _ in 0..<6{scroll.swipeUp()}
    XCTAssertLessThan(content.frame.minY,originalY-100)
    let proof=XCTAttachment(screenshot:XCUIScreen.main.screenshot());proof.name="Native code block scrolled to final lines";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testComposerRequiresASelectedChatInsteadOfDiscardingUnscopedText(){
    let app=launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:5))
    let composer=app.textFields["composer"]
    XCTAssertTrue(composer.exists);XCTAssertFalse(composer.isEnabled)
    app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout:4));row.tap()
    XCTAssertTrue(composer.waitForExistence(timeout:4));XCTAssertTrue(composer.isEnabled)
  }
  @MainActor private func launch(slow:Bool=false,share:Bool=false,noAnimations:Bool=false,extra:[String]=[])->XCUIApplication{
    XCUIDevice.shared.orientation = .portrait
    let app=XCUIApplication();app.launchArguments=["-ui-testing-native-app"]+(slow ? ["-slow-native-app-settings"]:[])+(share ? ["-artifact-test-save"]:[])+(noAnimations ? ["-native-fixture-no-animations"]:[])+extra;app.launchForNativeWindowQualification();return app
  }
  @MainActor func testNormalPendingSendDoesNotShowDeliveryUncertain(){
    let app=launch(extra:["-native-fixture-held-send"])
    openFixtureChat(app)
    let composer=app.textFields["composer"]
    composer.tap();composer.typeText("A normal pending send")
    app.buttons["send-message"].tap();allowSharing(app)
    app.buttons["send-message"].tap()
    XCTAssertFalse(app.buttons["send-message"].isEnabled)
    XCTAssertFalse(app.staticTexts["Delivery is uncertain"].waitForExistence(timeout:3))
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Normal send without false uncertainty";proof.lifetime = .keepAlways;add(proof)
    expectation(for:NSPredicate(format:"value == %@","Message OpenCode"),evaluatedWith:composer)
    waitForExpectations(timeout:12)
    XCTAssertFalse(app.staticTexts["Delivery is uncertain"].exists)
  }
  @MainActor func testFreeModelRejectionShowsUsefulExplanationWithoutRawDetails(){
    let app=launch(extra:["-native-fixture-provider-error"])
    openFixtureChat(app)
    let notice=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","OpenCode’s free-model service rejected this request.")).firstMatch
    XCTAssertTrue(notice.waitForExistence(timeout:5))
    XCTAssertFalse(app.staticTexts["The task ended with an error. Check your computer for details."].exists)
    XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","SYNTHETIC_PRIVATE_ERROR_DETAIL")).firstMatch.exists)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Safe actionable free-model failure";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor private func revealChatListControl(_ element:XCUIElement,in app:XCUIApplication){
    XCTAssertTrue(element.waitForExistence(timeout:5))
    // A partially visible row can be reported hittable behind the bottom bar.
    // Scroll the whole control clear of that bar before exercising its action.
    for _ in 0..<6{
      let bottom=app.buttons["Settings"].frame.minY
      if element.isHittable && element.frame.maxY<bottom-8{break}
      app.windows.firstMatch.swipeUp()
    }
    XCTAssertTrue(element.isHittable)
    XCTAssertLessThan(element.frame.maxY,app.buttons["Settings"].frame.minY-8)
  }
  @MainActor private func openFixtureChat(_ app:XCUIApplication){
    app.buttons["Open chat history"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    revealChatListControl(row,in:app);row.tap()
    expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["native-chatlist-done"])
    waitForExpectations(timeout:5)
    expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.textFields["composer"])
    waitForExpectations(timeout:5)
  }
  @MainActor private func allowSharing(_ app:XCUIApplication){
    XCTAssertTrue(app.staticTexts["sharing-unknown-destination"].waitForExistence(timeout:5))
    let allow=app.buttons["sharing-review-allow"]
    for _ in 0..<5{if allow.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(allow.isHittable);allow.tap()
    expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:allow)
    waitForExpectations(timeout:5)
  }
  @MainActor private func openDataControls(_ app:XCUIApplication){
    app.buttons["Open chat history"].tap();app.buttons["Settings"].tap()
    let data=app.buttons["native-local-data-open"]
    for _ in 0..<4{if data.exists && data.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(data.waitForExistence(timeout:4));data.tap()
    XCTAssertTrue(app.navigationBars["Data on this device"].waitForExistence(timeout:3))
  }
  @MainActor func testNativeResetReturnsToPairingAndExplainsServerAccessIsNotRevoked(){
    let app=launch(noAnimations:true)
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4));openDataControls(app)
    let reset=app.buttons["local-data-reset"]
    for _ in 0..<4{if reset.isHittable{break};app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(reset.isHittable);reset.tap();app.alerts.buttons["Reset local data"].tap()
    XCTAssertTrue(app.buttons["native-get-started"].waitForExistence(timeout:8))
    XCTAssertFalse(app.buttons["Model and chat settings"].exists)
    app.buttons["native-local-data-open"].tap()
    XCTAssertTrue(app.staticTexts["local-reset-report"].waitForExistence(timeout:4))
    XCTAssertTrue(app.staticTexts["local-reset-report"].label.contains("not revoked"))
  }
  @MainActor func testNativeClearSharingRequiresReviewAgainWithoutDiscardingDraft(){
    let app=launch(noAnimations:true)
    openFixtureChat(app)
    let composer=app.textFields["composer"];XCTAssertTrue(composer.waitForExistence(timeout:4));composer.tap();composer.typeText("Keep after clearing sharing")
    app.buttons["send-message"].tap();allowSharing(app)
    openDataControls(app)
    let sharing=app.buttons["local-data-sharing"]
    for _ in 0..<4{if sharing.isHittable{break};app.windows.firstMatch.swipeUp()}
    sharing.tap();app.alerts.buttons["Clear sharing permissions"].tap()
    app.navigationBars["Data on this device"].buttons.firstMatch.tap()
    app.buttons["native-connection-done"].tap();app.buttons["native-chatlist-done"].tap()
    XCTAssertEqual(composer.value as? String,"Keep after clearing sharing")
    XCTAssertTrue(app.buttons["send-message"].waitForExistence(timeout:5));app.buttons["send-message"].tap()
    XCTAssertTrue(app.buttons["sharing-review-cancel"].waitForExistence(timeout:5));app.buttons["sharing-review-cancel"].tap()
    XCTAssertEqual(composer.value as? String,"Keep after clearing sharing")
  }
  @MainActor func testNativeSharingReviewCancelKeepsDraftAndApprovalDoesNotAutoSend(){
    let app=launch(noAnimations:true)
    openFixtureChat(app)
    let composer=app.textFields["composer"];XCTAssertTrue(composer.waitForExistence(timeout:4));composer.tap();composer.typeText("Keep this draft until Send")
    app.buttons["send-message"].tap()
    XCTAssertTrue(app.buttons["sharing-review-cancel"].waitForExistence(timeout:5));app.buttons["sharing-review-cancel"].tap()
    XCTAssertEqual(composer.value as? String,"Keep this draft until Send")
    app.buttons["send-message"].tap();allowSharing(app)
    XCTAssertEqual(composer.value as? String,"Keep this draft until Send")
    app.buttons["send-message"].tap()
    expectation(for:NSPredicate(format:"value == %@","Message OpenCode"),evaluatedWith:composer)
    waitForExpectations(timeout:5)
  }
  @MainActor func testNativeConversationUsesExistingChatAndSettingsScreens(){
    let app=launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.staticTexts["Native project"].waitForExistence(timeout:3))
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:4))
    XCTAssertEqual(app.textFields["composer"].placeholderValue,"Message OpenCode")
    XCTAssertTrue(app.buttons["native-approval-open"].waitForExistence(timeout:4))
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:4))
    app.buttons["native-form-open"].tap()
    XCTAssertTrue(app.navigationBars["Answer OpenCode"].waitForExistence(timeout:4))
    app.buttons["native-form-close"].tap()
    app.buttons["Model and chat settings"].tap()
    XCTAssertTrue(app.buttons["native-model-picker"].waitForExistence(timeout:4))
    app.buttons["native-settings-done"].tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native shared conversation shell";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testNativeRenameBlankCancelAndLongPress(){
    let app=launch(noAnimations:true)
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:4))
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Rename"].tap()
    let field=app.textFields["chat-name"]
    XCTAssertTrue(field.waitForExistence(timeout:3));field.tap();field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:11))
    XCTAssertFalse(app.buttons["save-chat-name"].isEnabled)
    field.typeText("Discard this edit");app.buttons["Cancel"].tap()
    let row=app.buttons.containing(.staticText,identifier:"Native chat").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout:3));row.press(forDuration:1)
    XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout:3));app.buttons["Rename"].tap()
    XCTAssertEqual(app.textFields["chat-name"].value as? String,"Native chat")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:3))
  }
  @MainActor func testNativeVisibleRenameGroupsAndOlderTitleSearch(){
    let app=launch(noAnimations:true)
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:4))
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Rename"].tap()
    let field=app.textFields["chat-name"]
    XCTAssertTrue(field.waitForExistence(timeout:3));field.tap()
    field.press(forDuration:1)
    if app.menuItems["Select All"].waitForExistence(timeout:1){app.menuItems["Select All"].tap();field.typeText("Renamed native chat")}
    else{field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:11)+"Renamed native chat")}
    app.buttons["save-chat-name"].tap()
    XCTAssertTrue(app.buttons.containing(.staticText,identifier:"Renamed native chat").firstMatch.waitForExistence(timeout:5))
    app.buttons["groups-manage"].tap();app.buttons["native-group-new"].tap()
    let name=app.textFields["native-group-name"];XCTAssertTrue(name.waitForExistence(timeout:3));name.tap();name.typeText("Personal")
    app.buttons["native-group-save"].tap()
    XCTAssertTrue(app.staticTexts["Personal"].waitForExistence(timeout:3))
    app.buttons["native-groups-done"].tap()
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Move to group"].tap();app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-move-choice-")).firstMatch.tap()
    app.buttons["older-search-open"].tap()
    let search=app.searchFields.firstMatch;XCTAssertTrue(search.waitForExistence(timeout:3));search.tap();search.typeText("Renamed")
    XCTAssertTrue(app.buttons["native-search-hit-ses_owned"].waitForExistence(timeout:5))
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native chat rename groups and title search";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testNativeCreateForkAndExplicitTreeDeletion(){
    let app=launch()
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:4))
    app.buttons["chat-actions-ses_owned"].tap();app.buttons["Continue in a new chat"].tap()
    XCTAssertTrue(app.buttons["native-action-confirm"].waitForExistence(timeout:3));app.buttons["native-action-confirm"].tap()
    XCTAssertTrue(app.buttons["Model and chat settings"].waitForExistence(timeout:5))
    app.buttons["Open chat history"].tap()
    let forkActions=app.buttons["chat-actions-ses_fork"]
    revealChatListControl(forkActions,in:app);forkActions.tap()
    XCTAssertTrue(app.buttons["Delete chat and branches"].waitForExistence(timeout:3));app.buttons["Delete chat and branches"].tap()
    XCTAssertTrue(app.staticTexts["1 chat in this tree"].waitForExistence(timeout:4))
    app.buttons["native-action-confirm"].tap()
    XCTAssertTrue(app.buttons["chat-actions-ses_owned"].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["chat-actions-ses_fork"].exists)
    app.buttons["native-list-new-chat"].tap()
    XCTAssertTrue(app.buttons["Model and chat settings"].waitForExistence(timeout:5))
    app.buttons["Open chat history"].tap()
    XCTAssertTrue(app.buttons.containing(.staticText,identifier:"New chat").firstMatch.waitForExistence(timeout:4))
  }
  @MainActor func testNativeWorkingCopySkillsAndSkillOnlySend(){
    let app=launch(noAnimations:true)
    openFixtureChat(app)
    XCTAssertTrue(app.buttons["Model and chat settings"].waitForExistence(timeout:4));app.buttons["Model and chat settings"].tap()
    XCTAssertTrue(app.buttons["native-chat-changes-settings"].waitForExistence(timeout:4));app.buttons["native-chat-changes-settings"].tap()
    XCTAssertTrue(app.buttons["native-change-notes.txt"].waitForExistence(timeout:4));app.buttons["native-change-notes.txt"].tap()
    XCTAssertTrue(app.staticTexts["Added line: +new"].waitForExistence(timeout:4))
    app.navigationBars["Review change"].buttons.firstMatch.tap();app.buttons["native-changes-done"].tap();app.buttons["native-settings-done"].tap()
    app.buttons["composer-add"].tap();app.buttons["Skills"].tap()
    let skillSearch=app.searchFields.firstMatch;XCTAssertTrue(skillSearch.waitForExistence(timeout:3));skillSearch.tap();skillSearch.typeText("Review")
    XCTAssertTrue(app.buttons["native-skill-skill_owned"].waitForExistence(timeout:4));app.buttons["native-skill-skill_owned"].tap()
    XCTAssertTrue(app.staticTexts["Only review the fixture text."].waitForExistence(timeout:4))
    app.buttons["native-skill-use"].tap()
    XCTAssertTrue(app.buttons["selected-skill-skill_owned"].waitForExistence(timeout:4))
    XCTAssertTrue(app.buttons["send-message"].isEnabled);app.buttons["send-message"].tap()
    allowSharing(app);app.buttons["send-message"].tap()
    let cleared=NSPredicate(format:"exists == false")
    expectation(for:cleared,evaluatedWith:app.buttons["selected-skill-skill_owned"])
    waitForExpectations(timeout:5)
    // Returning from a sheet can leave the conversation above its latest row.
    // Follow the app's explicit control before querying lazy history content.
    if app.buttons["New replies"].exists{app.buttons["New replies"].tap()}
    XCTAssertTrue(app.staticTexts["Skill: Review fixture"].waitForExistence(timeout:4))
  }
  @MainActor func testNativeNewChatDefaultsSaveAndReset(){
    let app=launch(noAnimations:true)
    app.buttons["Open chat history"].tap();app.buttons["Settings"].tap()
    let entry=app.buttons["native-defaults-open"]
    for _ in 0..<3 where !entry.exists || !entry.isHittable{app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(entry.waitForExistence(timeout:4));entry.tap()
    XCTAssertTrue(app.buttons["native-default-model"].waitForExistence(timeout:4));app.buttons["native-default-model"].tap()
    let model=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-model-choice-")).firstMatch
    XCTAssertTrue(model.waitForExistence(timeout:4));model.tap();app.buttons["native-defaults-save"].tap()
    XCTAssertTrue(entry.waitForExistence(timeout:4));entry.tap()
    XCTAssertTrue(app.buttons["native-default-reset-all"].waitForExistence(timeout:4));app.buttons["native-default-reset-all"].tap();app.buttons["native-defaults-save"].tap()
    XCTAssertTrue(app.buttons["native-connection-done"].waitForExistence(timeout:4));app.buttons["native-connection-done"].tap()
    app.buttons["native-list-new-chat"].tap()
    XCTAssertTrue(app.buttons["Model and chat settings"].waitForExistence(timeout:5))
  }
  @MainActor func testNativeDoneRemainsIndependentOfSlowCatalog(){
    let app=launch(slow:true)
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    XCTAssertTrue(app.buttons["native-form-open"].waitForExistence(timeout:4))
    app.buttons["Model and chat settings"].tap()
    XCTAssertTrue(app.buttons["native-settings-done"].waitForExistence(timeout:3))
    app.buttons["native-settings-done"].tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
    app.buttons["native-approval-open"].tap()
    XCTAssertTrue(app.buttons["Allow once"].waitForExistence(timeout:3))
    app.buttons["Done"].tap()
    XCTAssertTrue(app.textFields["composer"].waitForExistence(timeout:2))
  }
  @MainActor func testNativePhotoSelectionAndFileOnlySend(){
    let app=launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    XCTAssertTrue(app.buttons["composer-add"].waitForExistence(timeout:4))
    app.buttons["composer-add"].tap();app.buttons["Photos or files"].tap()
    XCTAssertTrue(app.buttons["Choose photos"].waitForExistence(timeout:4))
    let sample=app.buttons["native-fixture-photo"]
    if !sample.isHittable{app.windows.firstMatch.swipeUp()}
    sample.tap()
    allowSharing(app)
    let retry=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-attachment-retry-")).firstMatch
    XCTAssertTrue(retry.waitForExistence(timeout:3));retry.tap()
    XCTAssertTrue(app.staticTexts["Ready · inline media"].waitForExistence(timeout:5))
    app.buttons["native-attachment-done"].tap()
    let chips=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-attachment-chip-"))
    XCTAssertEqual(chips.count,1)
    XCTAssertTrue(app.buttons["send-message"].isEnabled)
    app.buttons["send-message"].tap()
    let removed=NSPredicate{_,_ in chips.count==0}
    expectation(for:removed,evaluatedWith:nil)
    waitForExpectations(timeout:5)
  }

  @MainActor private func openResults(_ app:XCUIApplication){
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout:4))
    app.buttons["Open chat history"].tap()
    app.buttons.containing(.staticText,identifier:"Native chat").firstMatch.tap()
    let files=app.buttons["Files from this chat"]
    XCTAssertTrue(files.waitForExistence(timeout:4));files.tap()
  }
  @MainActor func testNativeResultPreviewAndExplicitShare(){
    let app=launch(share:true);openResults(app)
    let file=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","native-result-row-")).firstMatch
    XCTAssertTrue(file.waitForExistence(timeout:4));file.tap()
    XCTAssertTrue(app.staticTexts["Synthetic generated result\n"].waitForExistence(timeout:4))
    if app.frame.width>700{
      XCUIDevice.shared.orientation = .landscapeLeft
      let rotated=expectation(for:NSPredicate{_,_ in app.frame.width>app.frame.height},evaluatedWith:nil)
      wait(for:[rotated],timeout:5)
      XCTAssertTrue(app.buttons["native-result-share"].waitForExistence(timeout:3))
    }
    let share=app.buttons["native-result-share"]
    if !share.isHittable{app.windows.firstMatch.swipeUp()}
    XCTAssertTrue(share.isEnabled);share.tap()
    let save=app.cells["Save test copy"]
    XCTAssertTrue(save.waitForExistence(timeout:8))
    let actionable=expectation(for:NSPredicate(format:"hittable == true AND enabled == true"),evaluatedWith:save)
    wait(for:[actionable],timeout:5)
    save.press(forDuration:0.3)
    let saved=app.staticTexts["native-result-test-saved"]
    XCTAssertTrue(saved.waitForExistence(timeout:8))
    let expected=SHA256.hash(data:Data("Synthetic generated result\n".utf8)).map{String(format:"%02x",$0)}.joined()
    XCTAssertTrue(saved.label.contains(expected))
    XCTAssertTrue(app.staticTexts["Synthetic generated result\n"].exists)
    let proof=XCTAttachment(screenshot:app.screenshot());proof.name="Native result preview after explicit share";proof.lifetime = .keepAlways;add(proof)
  }
  @MainActor func testExplicitProjectFileBrowser(){
    let app=launch();openResults(app)
    app.buttons["native-project-files"].tap()
    XCTAssertTrue(app.buttons["project-only.txt"].waitForExistence(timeout:4));app.buttons["project-only.txt"].tap()
    XCTAssertTrue(app.staticTexts["Selected project file\n"].waitForExistence(timeout:4))
  }

}
