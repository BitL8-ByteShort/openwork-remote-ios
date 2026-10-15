import Foundation
import Testing
@testable import OpenWorkRemoteCore

actor NativeConversationTransport:HTTPTransport {
  private var requests:[URLRequest]=[]
  let moved:Bool
  let changed:Bool
  let oversizedAcknowledgement:Bool
  init(moved:Bool=false,changed:Bool=false,oversizedAcknowledgement:Bool=false){self.moved=moved;self.changed=changed;self.oversizedAcknowledgement=oversizedAcknowledgement}
  func data(for request:URLRequest) async throws -> (Data,Int) {
    requests.append(request)
    let path=request.url!.path
    if path == "/api/info" {return (Data(#"{"version":"2.0.29","urls":[],"paths":{"tmp":"/tmp/opencode"}}"#.utf8),200)}
    if path.hasSuffix("/interrupt") {return (Data(#"{"interrupted":false}"#.utf8),200)}
    if path.hasSuffix("/prompt") {
      if oversizedAcknowledgement{throw RemoteError.oversized}
      let input=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      let item:[String:Any]=["id":input["id"]!,"sessionID":"ses_owned","type":"user","delivery":"steer",
        "time":["created":1],"payload":["text":changed ? "First admitted body" : input["text"]!]]
      return (try JSONSerialization.data(withJSONObject:["data":item]),200)
    }
    let directory=moved ? "/different" : "/project"
    return (Data("{\"data\":{\"id\":\"ses_owned\",\"projectID\":\"project\",\"location\":{\"directory\":\"\(directory)\"},\"time\":{\"created\":1,\"updated\":2}}}".utf8),200)
  }
  func allRequests()->[URLRequest]{requests}
}
@Suite struct OpenCodeConversationTests {
  func setup(_ transport:any HTTPTransport) throws -> (OpenCodeClient,OpenCodeTarget) {
    let connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    return (try OpenCodeClient(connection:connection,token:"synthetic-token",transport:transport),
      OpenCodeTarget(connectionID:connection.id,projectID:"project",sessionID:"ses_owned",directory:"/project"))
  }
  @Test func promptAdmissionUsesStableNativeIDAndExactPayload() async throws {
    let transport=NativeConversationTransport(),(client,target)=try setup(transport)
    let prompt=try OpenCodePrompt(id:"msg_owned",text:"Synthetic prompt",resume:false)
    let admission=try await client.send(target:target,input:prompt)
    #expect(admission.id == prompt.id)
    #expect(admission.matches(prompt,sessionID:target.sessionID))
    let request=try #require(await transport.allRequests().last)
    #expect(request.url?.path == "/api/session/ses_owned/prompt")
    let body=try JSONSerialization.jsonObject(with:#require(request.httpBody)) as! [String:Any]
    #expect(body["resume"] as? Bool == false)
    #expect(body["id"] as? String == "msg_owned")
  }
  @Test func nativeFirstAdmissionWinsMustNotAcknowledgeEditedText() async throws {
    let (client,target)=try setup(NativeConversationTransport(changed:true))
    await #expect(throws:RemoteError.conflict) {
      _ = try await client.send(target:target,input:OpenCodePrompt(id:"msg_owned",text:"Edited text"))
    }
  }
  @Test func changedLocationOrAnotherConnectionCannotReceivePrompt() async throws {
    let transport=NativeConversationTransport(moved:true),(client,target)=try setup(transport)
    let prompt=try OpenCodePrompt(text:"Synthetic")
    await #expect(throws:RemoteError.conflict) {_ = try await client.send(target:target,input:prompt)}
    #expect(await transport.allRequests().contains{$0.httpMethod == "POST"} == false)
    let wrong=OpenCodeTarget(connectionID:ConnectionID(),projectID:target.projectID,sessionID:target.sessionID,directory:target.directory)
    await #expect(throws:RemoteError.invalidResponse) {_ = try await client.send(target:wrong,input:prompt)}
  }
  @Test func inactiveInterruptDoesNotInventAStoppedExecution() async throws {
    let (client,target)=try setup(NativeConversationTransport())
    #expect(try await client.interrupt(target:target) == false)
  }
  @Test func invalidPromptsFailBeforeNetworking() throws {
    #expect(throws:RemoteError.invalidResponse) {try OpenCodePrompt(id:"not-native",text:"Synthetic")}
    #expect(throws:RemoteError.invalidResponse) {try OpenCodePrompt(text:" \n ")}
    #expect(throws:RemoteError.oversized) {try OpenCodePrompt(text:String(repeating:"x",count:32_769))}
  }
  @Test func responseSizeFailureAfterPOSTIsAnUnknownAdmission() async throws {
    let transport=NativeConversationTransport(oversizedAcknowledgement:true),(client,target)=try setup(transport)
    await #expect(throws:RemoteError.outcomeUnknown){_ = try await client.send(target:target,input:OpenCodePrompt(text:"Synthetic"))}
    #expect(await transport.allRequests().filter{$0.httpMethod=="POST"}.count==1)
  }
}
