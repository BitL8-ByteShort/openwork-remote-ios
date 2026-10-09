import XCTest

/// Opt-in, owned disposable session only. Picker selection is injected here;
/// this proves the ordinary native state/HTTPS routes, not physical selection.
@MainActor final class LiveAttachmentUITests: XCTestCase {
  private struct Configuration: Decodable {
    struct Pairing: Decodable { let origin: String; let token: String }
    let pairing: Pairing
    let workspaceId: String
    let sessionId: String
  }
  func testPairedPhotoAndPDFProduceOneScopedPrompt() async throws {
    guard let path = ProcessInfo.processInfo.environment["OPENWORK_ATTACHMENT_UI_CONFIG"] else {
      throw XCTSkip("Live attachment qualification needs an explicit ephemeral pairing.")
    }
    continueAfterFailure = false
    let config = try JSONDecoder().decode(Configuration.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let checkpoint = URL(fileURLWithPath:path).deletingLastPathComponent().appending(path:"prompt-attempt.json")
    guard !FileManager.default.fileExists(atPath:checkpoint.path) else { throw XCTSkip("This qualification already attempted a prompt; use readback instead of sending again.") }
    var request = URLRequest(url:try XCTUnwrap(URL(string:config.pairing.origin + "/v1/workspaces/" + config.workspaceId + "/sessions/" + config.sessionId)))
    request.setValue("Bearer " + config.pairing.token,forHTTPHeaderField:"Authorization")
    let (data,response) = try await URLSession.shared.data(for:request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
    let session = try XCTUnwrap((try JSONSerialization.jsonObject(with:data) as? [String:Any])?["data"] as? [String:Any])
    XCTAssertEqual(session["title"] as? String,"Disposable remote attachments qualification")
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing-live-attachments","-attachment-fixture-files"]
    app.launchEnvironment["OPENWORK_ATTACHMENT_UI_CONFIG"] = path; app.launch()
    XCTAssertTrue(app.buttons["Add attachments"].waitForExistence(timeout:30)); app.buttons["Add attachments"].tap()
    let pdf = app.buttons["Use fixture PDF"]
    XCTAssertTrue(pdf.waitForExistence(timeout:15)); pdf.tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Ready to send")).firstMatch.waitForExistence(timeout:30))
    app.buttons["Use fixture photo"].tap()
    XCTAssertTrue(app.staticTexts["Photo.png"].waitForExistence(timeout:15))
    let ready = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Ready to send"))
    let uploadDeadline = Date().addingTimeInterval(30)
    while ready.count < 2, Date() < uploadDeadline { try await Task.sleep(for:.milliseconds(100)) }
    XCTAssertEqual(ready.count,2)
    app.buttons["attachment-done"].tap()
    let composer = app.textFields["composer"]; composer.tap()
    let prompt = "Disposable paired attachment qualification. Use only the two supplied files. State the color in the top-right quadrant of the image and the exact verification code printed in the PDF as COLOR; CODE. Do not inspect other files, use tools, change anything, or ask another question."
    composer.typeText(prompt)
    let send = app.buttons["send-message"]; XCTAssertTrue(send.isEnabled)
    try Data("{\"promptAttempted\":true,\"physicalSelectionQualified\":false}".utf8).write(to:checkpoint,options:[.atomic,.completeFileProtection])
    send.tap()
    XCTAssertTrue(app.buttons["Open chat history"].exists)
    // Wait for the accepted receipt to clear the actual draft, not the immediate
    // disabled-button presentation that happens before network dispatch.
    let admissionDeadline = Date().addingTimeInterval(30)
    while composer.value as? String == prompt, Date() < admissionDeadline { try await Task.sleep(for:.milliseconds(100)) }
    XCTAssertNotEqual(composer.value as? String,prompt)
    // Host-side readback checks bytes, model response and exact prompt count.
    app.terminate()
  }
}
