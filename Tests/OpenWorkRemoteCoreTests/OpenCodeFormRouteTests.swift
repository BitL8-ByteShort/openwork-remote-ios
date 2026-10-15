import Foundation
import Testing
@testable import OpenWorkRemoteCore

actor NativeFormTransport:HTTPTransport {
  var requests:[URLRequest]=[]
  var status="pending"
  var answer:[String:OpenCodeFormValue]?
  var changed=false
  var loseReply=false
  var stayPending=false
  private let fields=Data(#"[{"key":"choice","type":"string","required":true,"options":[{"value":"a","label":"A"}]}]"#.utf8)
  func data(for request:URLRequest) async throws -> (Data,Int){
    requests.append(request);let path=request.url!.path
    if path=="/api/info"{return(Data(#"{"version":"2.0.29","urls":[],"paths":{"tmp":"/tmp"}}"#.utf8),200)}
    if path=="/api/session/ses_owned"{return(Data(#"{"data":{"id":"ses_owned","projectID":"project","location":{"directory":"/project"},"time":{"created":1,"updated":2}}}"#.utf8),200)}
    if request.httpMethod=="POST"{
      if !stayPending{status="answered";answer=try JSONDecoder().decode([String:[String:OpenCodeFormValue]].self,from:request.httpBody!)["answer"]}
      if loseReply{throw URLError(.networkConnectionLost)}
      return(Data(),204)
    }
    if request.httpMethod=="DELETE"{status="cancelled";return(Data(),204)}
    var value:[String:Any]=["id":"frm_owned","sessionID":"ses_owned","title":changed ? "New question" : "Choose","fields":try JSONSerialization.jsonObject(with:fields),"state":["status":status]]
    if let answer{value["state"]=["status":status,"answer":try JSONSerialization.jsonObject(with:JSONEncoder().encode(answer))]}
    return(try JSONSerialization.data(withJSONObject:["data":value]),200)
  }
  func changeDefinition(){changed=true}
  func loseNextReply(remainPending:Bool=false){loseReply=true;stayPending=remainPending}
  func allRequests()->[URLRequest]{requests}
}
@Suite struct OpenCodeFormRouteTests {
  func setup(_ transport:NativeFormTransport)throws->(OpenCodeClient,OpenCodeTarget){
    let connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    return(try OpenCodeClient(connection:connection,token:"synthetic",transport:transport),OpenCodeTarget(connectionID:connection.id,projectID:"project",sessionID:"ses_owned",directory:"/project"))
  }
  @Test func explicitReplyReadbackAndDesktopSettledRaceNeverReplay() async throws {
    let transport=NativeFormTransport(),(client,target)=try setup(transport)
    let form=try await client.form(target:target,id:"frm_owned")
    #expect(try await client.replyForm(target:target,form:form,answer:["choice":.string("a")]) == .confirmed)
    #expect(try await client.replyForm(target:target,form:form,answer:["choice":.string("a")]) == .alreadyResolved)
    #expect(await transport.allRequests().filter{$0.httpMethod=="POST"}.count==1)
  }
  @Test func changedFieldsAreRejectedBeforeAnyReply() async throws {
    let transport=NativeFormTransport(),(client,target)=try setup(transport)
    let form=try await client.form(target:target,id:"frm_owned");await transport.changeDefinition()
    await #expect(throws:OpenCodeFormNotSubmitted(reason:.conflict)){
      _ = try await client.replyForm(target:target,form:form,answer:["choice":.string("a")])
    }
    #expect(await transport.allRequests().contains{$0.httpMethod=="POST"}==false)
  }
  @Test func lostReplyChecksNativeStateWithoutResubmitting() async throws {
    let transport=NativeFormTransport(),(client,target)=try setup(transport)
    let form=try await client.form(target:target,id:"frm_owned");await transport.loseNextReply()
    #expect(try await client.replyForm(target:target,form:form,answer:["choice":.string("a")]) == .confirmed)
    #expect(await transport.allRequests().filter{$0.httpMethod=="POST"}.count==1)
  }
  @Test func pendingAfterLostReplyRemainsUncertain() async throws {
    let transport=NativeFormTransport(),(client,target)=try setup(transport)
    let form=try await client.form(target:target,id:"frm_owned");await transport.loseNextReply(remainPending:true)
    await #expect(throws:RemoteError.outcomeUnknown){_ = try await client.replyForm(target:target,form:form,answer:["choice":.string("a")])}
    #expect(await transport.allRequests().filter{$0.httpMethod=="POST"}.count==1)
  }
}
