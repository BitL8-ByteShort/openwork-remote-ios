import Foundation
import Testing
@testable import OpenWorkRemoteCore

actor NativeEventTransport:HTTPTransport {
  private var request:URLRequest?
  let frames:[SSEFrame]
  init(_ frames:[SSEFrame]){self.frames=frames}
  func data(for request:URLRequest) async throws -> (Data,Int){throw RemoteError.unavailable}
  func events(for request:URLRequest) async throws -> AsyncThrowingStream<SSEFrame,any Error>{
    self.request=request
    return AsyncThrowingStream{continuation in
      for frame in frames{continuation.yield(frame)}
      continuation.finish()
    }
  }
  func savedRequest()->URLRequest?{request}
}
@Suite struct OpenCodeStreamTests {
  func frame(_ json:String)->SSEFrame{SSEFrame(event:"message",id:nil,data:json)}
  @Test func typedEventsUseNativeEndpointWithoutPretendingToReplay() async throws {
    let transport=NativeEventTransport([
      frame(#"{"id":"evt_1","type":"session.text.delta","location":{"directory":"/project"},"data":{"sessionID":"ses_owned","assistantMessageID":"msg_assistant","ordinal":0,"delta":"Hello"}}"#),
      frame(#"{"id":"evt_2","type":"future.native.event","data":{"sessionID":"ses_other","private":"never display raw data"}}"#)
    ])
    let connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic-token",transport:transport)
    var events:[OpenCodeEvent]=[]
    for try await event in try await client.events(){events.append(event)}
    #expect(events.count==2)
    #expect(events.first?.data.delta=="Hello")
    let target=OpenCodeTarget(connectionID:connection.id,projectID:"project",sessionID:"ses_owned",directory:"/project")
    #expect(events.first?.affects(target)==true)
    #expect(events.last?.affects(target)==false)
    let request=try #require(await transport.savedRequest())
    #expect(request.url?.path=="/api/event")
    #expect(request.url?.query==nil)
    #expect(request.value(forHTTPHeaderField:"Last-Event-ID")==nil)
    #expect(request.value(forHTTPHeaderField:"Accept")=="text/event-stream")
  }
  @Test func malformedAndOversizedEventsRequireSnapshotRecovery() throws {
    #expect(throws:RemoteError.invalidResponse){try OpenCodeEvent.decode(frame(#"{"id":"evt_bad","type":"session.text.delta","data":{"ordinal":-1}}"#))}
    #expect(throws:RemoteError.oversized){try OpenCodeEvent.decode(frame(String(repeating:"x",count:262_145)))}
    #expect(throws:RemoteError.invalidResponse){try OpenCodeEvent.decode(frame("{"))}
  }
}
