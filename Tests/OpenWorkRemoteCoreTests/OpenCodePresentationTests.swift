import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodePresentationTests {
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
  @Test func globalProjectDoesNotPresentFilesystemRootAsAChosenProject() throws {
    let native=try JSONDecoder().decode(OpenCodeProject.self,from:Data(#"{"id":"global","canonical":"/","sandboxes":[],"time":{"created":1,"updated":1,"active":1}}"#.utf8))
    #expect(native.presentation.name=="Other folders")
  }
}
