import XCTest

/// Read-only, opt-in qualification against an explicitly owned result chat.
/// It does not prompt the model or read/save the user's durable pairing.
@MainActor final class LiveArtifactUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable { let origin: String; let token: String }
    let pairing: Pairing
    let workspaceId: String
    let sessionId: String
  }
  func testPairedRepairedFixturePNGCanBePreviewedAndExplicitlyShared() async throws {
    guard let path=ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else {throw XCTSkip("Needs an explicit owned fixture pairing.")}
    continueAfterFailure=false
    let config=try JSONDecoder().decode(Configuration.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let base=config.pairing.origin+"/v1/workspaces/"+config.workspaceId+"/sessions/"+config.sessionId
    var request=URLRequest(url:try XCTUnwrap(URL(string:base+"/artifacts")))
    request.setValue("Bearer "+config.pairing.token,forHTTPHeaderField:"Authorization")
    let (data,response)=try await URLSession.shared.data(for:request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
    let catalog=try XCTUnwrap((try JSONSerialization.jsonObject(with:data) as? [String:Any])?["data"] as? [String:Any])
    let refs=try XCTUnwrap(catalog["items"] as? [[String:Any]])
    let ref=try XCTUnwrap(refs.first {$0["name"] as? String == "preview.png"})
    let app=XCUIApplication();app.launchArguments=["-ui-testing-live-artifacts","-artifact-test-save"]
    app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"]=path;app.launch()
    let settings=app.buttons["Model and chat settings"];XCTAssertTrue(settings.waitForExistence(timeout:30));settings.tap()
    let files=app.buttons["chat-files-settings"];XCTAssertTrue(files.waitForExistence(timeout:15));files.tap()
    let row=app.buttons["artifact-row-"+(try XCTUnwrap(ref["id"] as? String))]
    XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
    XCTAssertTrue(app.images["Preview of preview.png"].waitForExistence(timeout:15))
    let share=app.buttons["Share or save a copy"];XCTAssertTrue(share.isEnabled);share.tap()
    let save=app.cells["Save test copy"];XCTAssertTrue(save.waitForExistence(timeout:15));save.tap()
    XCTAssertTrue(app.staticTexts["Test copy saved: "+(try XCTUnwrap(ref["sha256"] as? String))].waitForExistence(timeout:15))
    XCTAssertTrue(share.isEnabled);app.terminate()
  }
  func testPairedNativeResultsPreviewShareAndRejectDamagedImage() async throws {
    guard let path=ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else {
      throw XCTSkip("Live result qualification needs an explicit temporary pairing.")
    }
    continueAfterFailure=false
    let config=try JSONDecoder().decode(Configuration.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let base=config.pairing.origin+"/v1/workspaces/"+config.workspaceId+"/sessions/"+config.sessionId
    func read(_ url: String) async throws -> [String:Any] {
      var request=URLRequest(url:try XCTUnwrap(URL(string:url)))
      request.setValue("Bearer "+config.pairing.token,forHTTPHeaderField:"Authorization")
      let (data,response)=try await URLSession.shared.data(for:request)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
      return try XCTUnwrap((try JSONSerialization.jsonObject(with:data) as? [String:Any])?["data"] as? [String:Any])
    }
    let ownedSession=try await read(base)
    XCTAssertEqual(ownedSession["title"] as? String,"Disposable remote results qualification")
    let catalog=try await read(base+"/artifacts")
    let refs=try XCTUnwrap(catalog["items"] as? [[String:Any]])
    let app=XCUIApplication();app.launchArguments=["-ui-testing-live-artifacts","-artifact-test-save"]
    app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"]=path;app.launch()
    let settings=app.buttons["Model and chat settings"];XCTAssertTrue(settings.waitForExistence(timeout:30));settings.tap()
    let files=app.buttons["chat-files-settings"];XCTAssertTrue(files.waitForExistence(timeout:15));files.tap()
    func row(_ name: String) throws -> XCUIElement {
      let ref=try XCTUnwrap(refs.first {$0["name"] as? String == name})
      let id=try XCTUnwrap(ref["id"] as? String)
      let row=app.buttons["artifact-row-"+id];XCTAssertTrue(row.waitForExistence(timeout:15));return row
    }
    try row("notes.txt").tap()
    let share=app.buttons["Share or save a copy"]
    XCTAssertTrue(share.waitForExistence(timeout:10))
    let deadline=Date().addingTimeInterval(15)
    while !share.isEnabled,Date()<deadline { try await Task.sleep(for:.milliseconds(100)) }
    XCTAssertTrue(share.isEnabled)
    app.navigationBars.buttons["Files from this chat"].tap()
    try row("report.pdf").tap()
    XCTAssertTrue(app.images["PDF page 1 of 1"].waitForExistence(timeout:20))
    share.tap()
    let save=app.cells["Save test copy"];XCTAssertTrue(save.waitForExistence(timeout:15));save.tap()
    let checksum=try XCTUnwrap(refs.first {$0["name"] as? String == "report.pdf"}?["sha256"] as? String)
    XCTAssertTrue(app.staticTexts["Test copy saved: "+checksum].waitForExistence(timeout:15))
    XCTAssertTrue(share.isEnabled)
    app.navigationBars.buttons["Files from this chat"].tap()
    try row("preview.png").tap()
    XCTAssertTrue(app.staticTexts["This file could not be previewed. It may be damaged or unsupported. Check it on your computer."].waitForExistence(timeout:15))
    XCTAssertFalse(share.isEnabled)
    XCUIDevice.shared.press(.home);try await Task.sleep(for:.seconds(1));app.activate()
    XCTAssertTrue(app.staticTexts["This chat or connection changed. Open the file again from your current chat."].waitForExistence(timeout:15))
    XCTAssertFalse(share.isEnabled)
    app.terminate()
  }
}
