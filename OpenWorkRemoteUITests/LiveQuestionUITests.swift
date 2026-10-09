import XCTest

/// Explicitly enabled with an ephemeral, scoped pairing prepared on the host.
/// Normal CI skips these tests; they never load the installed phone's credential.
final class LiveQuestionUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable { let origin: String; let token: String }
    let pairing: Pairing
    let workspaceId: String
    let sessionId: String
    let questionId: String
    let firstOptionValue: String
    let textKey: String
    let signalsDirectory: String
  }
  private struct SessionRead: Decodable {
    struct Session: Decodable { let id: String; let title: String }
    let data: Session
  }
  @MainActor private func open() async throws -> (XCUIApplication, Configuration) {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_QUESTION_UI_CONFIG"] else {
      throw XCTSkip("Live host qualification is explicitly enabled with an ephemeral pairing.")
    }
    let config = try JSONDecoder().decode(Configuration.self,
      from: Data(contentsOf: URL(fileURLWithPath: path)))
    continueAfterFailure = false
    let url = try XCTUnwrap(URL(string: config.pairing.origin + "/v1/workspaces/"
      + config.workspaceId + "/sessions/" + config.sessionId))
    var request = URLRequest(url: url)
    request.setValue("Bearer " + config.pairing.token, forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    let scope = try JSONDecoder().decode(SessionRead.self, from: data).data
    XCTAssertEqual(scope.id, config.sessionId)
    XCTAssertEqual(scope.title, "Disposable remote questions qualification")
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-live-questions"]
    app.launchEnvironment["OPENWORK_QUESTION_UI_CONFIG"] = path
    app.launch()
    XCTAssertTrue(app.buttons["Open chat history"].waitForExistence(timeout: 30))
    let banner = app.buttons["question-banner"]
    XCTAssertTrue(banner.waitForExistence(timeout: 30)); banner.tap()
    XCTAssertTrue(app.buttons["question-option-" + config.firstOptionValue].waitForExistence(timeout: 10))
    app.buttons["question-option-" + config.firstOptionValue].tap()
    app.buttons["question-next"].tap()
    return (app, config)
  }
  @MainActor func testPairedHTTPSAnswersAndRetainedDraft() async throws {
    let (app, config) = try await open()
    let text = app.textFields["question-text-" + config.textKey]
    XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Paired fixture project")
    app.buttons["Cancel"].tap()
    app.buttons["question-banner"].tap(); app.buttons["question-next"].tap()
    XCTAssertEqual(app.textFields["question-text-" + config.textKey].value as? String, "Paired fixture project")
    app.buttons["question-send"].tap()
    XCTAssertTrue(app.staticTexts["Answers sent."].waitForExistence(timeout: 30))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Live paired HTTPS - answers acknowledged"; screenshot.lifetime = .keepAlways; add(screenshot)
    app.terminate()
  }
  @MainActor func testComputerAnswerWhileSheetOpenKeepsPhoneDraft() async throws {
    let (app, config) = try await open()
    let text = app.textFields["question-text-" + config.textKey]
    XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Retained phone draft")
    let directory = URL(fileURLWithPath: config.signalsDirectory, isDirectory: true)
    let signal = try JSONEncoder().encode(["questionId": config.questionId])
    try signal.write(to: directory.appending(path: "desktop-answer-requested.json"), options: .atomic)
    let changed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "no longer pending")).firstMatch
    XCTAssertTrue(changed.waitForExistence(timeout: 30))
    XCTAssertEqual(text.value as? String, "Retained phone draft")
    XCTAssertFalse(app.buttons["question-send"].isEnabled)
    XCTAssertFalse(app.staticTexts["Answers sent."].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Computer answered - phone draft retained"; screenshot.lifetime = .keepAlways; add(screenshot)
    app.terminate()
  }
}
