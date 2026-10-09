import XCTest
@MainActor final class LiveWorkspaceDefaultsUITests:XCTestCase {
 private struct Configuration:Decodable {
  struct Pairing:Decodable{let origin:String,token:String}
  let pairing:Pairing,workspaceId:String,sessionId:String,defaultsOptionId:String,defaultsModelName:String
 }
 func testPairedPhoneSavesDefaultOnlyForItsDisposableWorkspace()async throws {
  guard let path=ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else{throw XCTSkip("Requires temporary paired disposable default workspace")}
  continueAfterFailure=false;let c=try JSONDecoder().decode(Configuration.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
  let app=XCUIApplication();app.launchArguments=["-ui-testing-live-artifacts"];app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"]=path;app.launch()
  let history=app.buttons["Open chat history"];XCTAssertTrue(history.waitForExistence(timeout:30));history.tap();app.buttons["Settings"].tap()
  let workspace=app.buttons["workspace-settings-open"];XCTAssertTrue(workspace.waitForExistence(timeout:10));workspace.tap();app.buttons["workspace-defaults-open"].tap()
  let picker=app.buttons["workspace-defaults-model"];XCTAssertTrue(picker.waitForExistence(timeout:20));picker.tap()
  let option=app.buttons["model-option-"+c.defaultsOptionId];XCTAssertTrue(option.waitForExistence(timeout:10));option.tap()
  let save=app.buttons["workspace-defaults-save"];let ready=expectation(for:NSPredicate(format:"enabled == YES"),evaluatedWith:save);await fulfillment(of:[ready],timeout:10);save.tap()
  let current=app.staticTexts["workspace-defaults-current"];let saved=expectation(for:NSPredicate(format:"label CONTAINS %@",c.defaultsModelName),evaluatedWith:current);await fulfillment(of:[saved],timeout:15)
  var req=URLRequest(url:URL(string:c.pairing.origin+"/v1/workspaces/"+c.workspaceId+"/default-model")!);req.setValue("Bearer "+c.pairing.token,forHTTPHeaderField:"Authorization")
  let(bytes,response)=try await URLSession.shared.data(for:req);XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
  let root=try XCTUnwrap(try JSONSerialization.jsonObject(with:bytes) as? [String:Any]),snapshot=try XCTUnwrap(root["data"] as? [String:Any]);XCTAssertTrue(snapshot["current"] is [String:Any])
 }
}
