import XCTest

@MainActor final class LiveSearchUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable { let origin: String, token: String }
    let pairing: Pairing
    let workspaceId: String, sessionId: String, note: String
  }
  func testPairedOlderTitleSearchFindsScopedNativeChatAndOpensIt() async throws {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_ARTIFACT_UI_CONFIG"] else {
      throw XCTSkip("Requires temporary paired read-only host qualification")
    }
    continueAfterFailure = false
    let c = try JSONDecoder().decode(
      Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    var parts = URLComponents(
      string: c.pairing.origin + "/v1/workspaces/" + c.workspaceId + "/sessions/search")!
    parts.queryItems = [URLQueryItem(name: "q", value: c.note)]
    var req = URLRequest(url: parts.url!)
    req.setValue("Bearer " + c.pairing.token, forHTTPHeaderField: "Authorization")
    let (bytes, response) = try await URLSession.shared.data(for: req)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let page = try XCTUnwrap(envelope["data"] as? [String: Any])
    let rows = try XCTUnwrap(page["data"] as? [[String: Any]])
    XCTAssertTrue(rows.contains { $0["id"] as? String == c.sessionId })
    XCTAssertTrue(rows.allSatisfy { $0["workspaceId"] as? String == c.workspaceId })
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-live-artifacts"]
    app.launchEnvironment["OPENWORK_ARTIFACT_UI_CONFIG"] = path
    app.launch()
    let history = app.buttons["Open chat history"]
    XCTAssertTrue(history.waitForExistence(timeout: 30))
    history.tap()
    let open = app.buttons["older-search-open"]
    XCTAssertTrue(open.waitForExistence(timeout: 10))
    open.tap()
    let field = app.textFields["older-search-query"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(c.note)
    let result = app.buttons["older-search-result-" + c.sessionId]
    XCTAssertTrue(result.waitForExistence(timeout: 15))
    result.tap()
    XCTAssertTrue(history.waitForExistence(timeout: 3))
    XCTAssertFalse(field.exists)
  }
}
