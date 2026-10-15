import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodePresentationTests {
  @Test func freeModelRejectionExplainsProviderFailureWithoutRepeatingPrivateErrorDetails() throws {
    let raw = #"{"id":"msg_free","type":"assistant","time":{"created":1,"completed":2},"content":[],"error":{"type":"provider.auth","status":403,"message":"OpenCode's free tier can only be used from within OpenCode. SYNTHETIC_PRIVATE_TOKEN https://private.invalid/path","response":{"body":"SYNTHETIC_PRIVATE_BODY"}}}"#
    let native = try JSONDecoder().decode(OpenCodeMessage.self, from: Data(raw.utf8))
    let shown = try #require(native.presentation(sessionID: "ses_owned", active: false))
    #expect(shown.state == "error")
    #expect(shown.blocks.filter { $0.kind == "error" }.map(\.text) == ["OpenCode’s free-model service rejected this request. Try a new chat, review the model and tool rules in OpenCode, or choose another configured model."])
    let encoded = String(decoding: try JSONEncoder().encode(shown), as: UTF8.self)
    #expect(!encoded.contains("SYNTHETIC_PRIVATE"))
    #expect(!encoded.contains("private.invalid"))
  }
  @Test func unrelatedOrMalformedErrorsKeepTheGenericFailureWithoutInventingAFreeModelRestriction() throws {
    let errors: [Any] = [
      ["type": "provider.auth", "status": 403, "message": "SYNTHETIC_PRIVATE_AUTH_DETAIL"],
      ["type": "other", "status": 403, "message": "OpenCode's free tier can only be used from within OpenCode."],
      ["type": "provider.auth", "status": 401, "message": "OpenCode's free tier can only be used from within OpenCode."],
      ["type": "provider.auth", "status": 403, "message": String(repeating: "x", count: 8_193)],
      ["future": "SYNTHETIC_PRIVATE_FIELD"], ["unexpected", "error", "shape"]
    ]
    for error in errors {
      let raw: [String: Any] = ["id": "msg_error", "type": "assistant", "time": ["created": 1], "content": [], "error": error]
      let native = try JSONDecoder().decode(OpenCodeMessage.self, from: JSONSerialization.data(withJSONObject: raw))
      let shown = try #require(native.presentation(sessionID: "ses_owned", active: false))
      #expect(shown.state == "error")
      #expect(!shown.blocks.contains { $0.kind == "error" })
      #expect(!String(decoding: try JSONEncoder().encode(shown), as: UTF8.self).contains("SYNTHETIC_PRIVATE"))
    }
  }
  @Test func finalTextBesideToolsSurvivesPresentationAndLiveTextUsesTextOrdinal() throws {
    let native=try JSONDecoder().decode(OpenCodeMessage.self,from:Data(#"{"id":"msg_answer","type":"assistant","time":{"created":1},"content":[{"type":"text","text":"Before"},{"type":"tool","name":"read","state":{"status":"completed","content":[{"type":"text","text":"Synthetic output"}]}},{"type":"text","text":"Final"}]}"#.utf8))
    let item=try #require(native.presentation(sessionID:"ses_owned",active:true,liveText:{ordinal in ordinal==1 ? "Final streaming answer" : nil}))
    #expect(item.blocks.map(\.kind)==["text","tool","text"])
    #expect(item.blocks.last?.text=="Final streaming answer")
    #expect(item.state=="streaming")
  }
  @Test func unknownContentCannotExposeUnmodeledPrivateFields() throws {
    let native=try JSONDecoder().decode(OpenCodeMessage.self,from:Data(#"{"id":"msg_future","type":"future-item","time":{"created":1},"private":"never render"}"#.utf8))
    let item=try #require(native.presentation(sessionID:"ses_owned",active:false))
    #expect(item.role=="system")
    #expect(item.blocks.first?.text=="This item is available on your computer.")
    #expect(item.blocks.first?.text?.contains("never render")==false)
  }
  @Test func fileAndSkillOnlyMessagesHaveLabelsWithoutRenderingSkillInstructions()throws{
    let raw=#"{"id":"msg_context","type":"user","text":"","time":{"created":1},"files":[{"name":"sample.pdf","mime":"application/pdf","data":"AQID","source":{"type":"inline"}}],"skills":[{"id":"skill_owned","name":"Review fixture","text":"Private materialized instructions should not render"}]}"#
    let native=try JSONDecoder().decode(OpenCodeMessage.self,from:Data(raw.utf8))
    let shown=try #require(native.presentation(sessionID:"ses_owned",active:false))
    #expect(shown.blocks.contains{$0.label=="File: sample.pdf"})
    #expect(shown.blocks.contains{$0.label=="Skill: Review fixture"})
    #expect(!shown.blocks.contains{($0.text ?? $0.label ?? "").contains("Private materialized")})
  }
  @Test func globalProjectDoesNotPresentFilesystemRootAsAChosenProject() throws {
    let native=try JSONDecoder().decode(OpenCodeProject.self,from:Data(#"{"id":"global","canonical":"/","sandboxes":[],"time":{"created":1,"updated":1,"active":1}}"#.utf8))
    #expect(native.presentation.name=="Other folders")
  }
}
