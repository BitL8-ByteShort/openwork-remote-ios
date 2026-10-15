import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite struct OpenCodeLiveTextTests {
  func event(_ kind:String,text:String?=nil,delta:String?=nil) throws -> OpenCodeEvent {
    var fields:[String:Any]=["sessionID":"ses_owned","assistantMessageID":"msg_answer","ordinal":0]
    fields["text"]=text;fields["delta"]=delta
    let bytes=try JSONSerialization.data(withJSONObject:["id":UUID().uuidString,"type":"session.text."+kind,"data":fields])
    return try OpenCodeEvent.decode(SSEFrame(event:"message",id:nil,data:String(decoding:bytes,as:UTF8.self)))
  }
  @Test func missingStartCannotDisplayATruncatedAnswerAfterReconnect() throws {
    var buffer=NativeLiveTextBuffer()
    #expect(try buffer.receive(event("delta",delta:"middle")) == .needsSnapshot)
    #expect(buffer.text(messageID:"msg_answer",ordinal:0)==nil)
    _ = try buffer.receive(event("ended",text:"Whole answer"))
    #expect(buffer.text(messageID:"msg_answer",ordinal:0)=="Whole answer")
  }
  @Test func deltasAreReplacedByAuthoritativeBoundaryThenRetiredBySnapshot() throws {
    var buffer=NativeLiveTextBuffer()
    _ = try buffer.receive(event("started"));_ = try buffer.receive(event("delta",delta:"Hello"))
    _ = try buffer.receive(event("delta",delta:" there"))
    #expect(buffer.text(messageID:"msg_answer",ordinal:0)=="Hello there")
    _ = try buffer.receive(event("ended",text:"Hello there!"))
    let message=try JSONDecoder().decode(OpenCodeMessage.self,from:Data(#"{"id":"msg_answer","type":"assistant","content":[{"type":"tool","name":"read","state":{"status":"completed"}},{"type":"text","text":"Hello there!"}],"time":{"created":1}}"#.utf8))
    buffer.confirmed(by:[message])
    #expect(buffer.text(messageID:"msg_answer",ordinal:0)==nil)
  }
  @Test func anOversizedAnswerDropsTransientTextAndRequiresReadback() throws {
    var buffer=NativeLiveTextBuffer()
    _ = try buffer.receive(event("started"))
    for _ in 0..<4{_ = try buffer.receive(event("delta",delta:String(repeating:"x",count:65_536)))}
    #expect(try buffer.receive(event("delta",delta:"overflow")) == .needsSnapshot)
    #expect(buffer.text(messageID:"msg_answer",ordinal:0)==nil)
  }
}
