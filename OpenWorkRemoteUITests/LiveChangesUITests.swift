import XCTest

/// Opt-in reads against a disposable native workspace, through a temporary
/// scoped pairing. No prompt, tool execution or file-writing phone action.
@MainActor final class LiveChangesUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable {let origin: String;let token: String}
    let pairing: Pairing
    let workspaceId: String
    let sessionId: String
  }
  func testPairedNativeWorkspaceChangesAreReadableWithoutApplyingAnything() async throws {
    guard let path=ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else {throw XCTSkip("Needs an explicit disposable workspace pairing.")}
    continueAfterFailure=false
    let config=try JSONDecoder().decode(Configuration.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let base=config.pairing.origin+"/v1/workspaces/"+config.workspaceId+"/sessions/"+config.sessionId
    func read(_ path: String) async throws -> [String:Any] {
      var request=URLRequest(url:try XCTUnwrap(URL(string:base+path)))
      request.setValue("Bearer "+config.pairing.token,forHTTPHeaderField:"Authorization")
      let (data,response)=try await URLSession.shared.data(for:request)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
      return try XCTUnwrap((try JSONSerialization.jsonObject(with:data) as? [String:Any])?["data"] as? [String:Any])
    }
    let owned=try await read("")
    XCTAssertEqual(owned["title"] as? String,"Disposable workspace changes qualification")
    let catalog=try await read("/changes")
    XCTAssertEqual(catalog["provenance"] as? String,"workspace")
    let refs=try XCTUnwrap(catalog["files"] as? [[String:Any]])
    XCTAssertTrue(refs.contains {$0["pathLabel"] as? String == "unrelated.txt"})
    let app=XCUIApplication();app.launchArguments=["-ui-testing-live-artifacts"]
    app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"]=path;app.launch()
    let settings=app.buttons["Model and chat settings"];XCTAssertTrue(settings.waitForExistence(timeout:30));settings.tap()
    let changes=app.buttons["workspace-changes-settings"];XCTAssertTrue(changes.waitForExistence(timeout:15));changes.tap()
    let row=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","existing.txt")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@","Added line: +after")).firstMatch.waitForExistence(timeout:15))
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@","Removed line: -before")).firstMatch.exists)
    let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Native paired workspace diff";attachment.lifetime = .keepAlways;add(attachment)
    XCTAssertFalse(app.buttons["Apply"].exists);XCTAssertFalse(app.buttons["Revert"].exists)
    app.terminate()
  }
}
