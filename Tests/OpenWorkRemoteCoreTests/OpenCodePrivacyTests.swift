import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor NativePrivacyTransport:HTTPTransport{
  var endpoint="https://user:private@provider.example/v1?key=private"
  var provider="Local-looking alias"
  var posts=0
  func setEndpoint(_ value:String){endpoint=value}
  func counts()->Int{posts}
  func data(for r:URLRequest)async throws->(Data,Int){
    let path=r.url!.path,value:Any
    if r.httpMethod=="POST"{posts+=1;throw RemoteError.unavailable}
    if path=="/api/info"{value=["version":"2.0.29","urls":[],"paths":["tmp":"/tmp/native"]]}
    else if path=="/api/session/ses_owned/form/frm_owned"{value=["data":["id":"frm_owned","sessionID":"ses_owned","title":"Answer","fields":[["key":"answer","type":"string","required":true]],"state":["status":"pending"]]]}
    else if path=="/api/session/ses_owned"{value=["data":["id":"ses_owned","projectID":"project","location":["directory":"/project"],"model":["providerID":provider,"id":"model"],"time":["created":1,"updated":2]]]}
    else if path=="/api/model"{value=["location":["directory":"/project"],"data":[["providerID":provider,"id":"model","modelID":"model","name":"Model","enabled":true,"status":"active","variants":[],"package":"@provider/package","settings":["baseURL":endpoint,"apiKey":"do-not-persist-key"],"headers":["Authorization":"do-not-persist-header"],"capabilities":["tools":true,"input":["text"],"output":["text"]]]]]}
    else{throw RemoteError.invalidResponse}
    return(try JSONSerialization.data(withJSONObject:value),200)
  }
}
@Suite struct OpenCodePrivacyTests{
  @Test func sharingGuardAlsoStopsStagedUploadsAndQuestionAnswersBeforeTheirPosts()async throws{
    let t=NativePrivacyTransport(),c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:c,token:"synthetic",transport:t)
    let target=OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_owned",directory:"/project")
    await client.observeSharingAuthorization{_,_,_ in throw RemoteError.forbidden}
    let model=try await client.attachmentModel(target:target)
    await #expect(throws:RemoteError.forbidden){try await client.prepareAttachment(bytes:Data("%PDF-1.7\nowned fixture\n%%EOF".utf8),name:"owned.pdf",mime:"application/pdf",target:target,model:model)}
    let form=try await client.form(target:target,id:"frm_owned")
    await #expect(throws:OpenCodeFormNotSubmitted(reason:.forbidden)){try await client.replyForm(target:target,form:form,answer:["answer":.string("Kept on phone")])}
    #expect(await t.counts()==0)
  }
  @Test func reportedProviderNeverBecomesAnInventedVerifiedOrLocalDestination()async throws{
    let t=NativePrivacyTransport(),c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:c,token:"synthetic",transport:t)
    let target=OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_owned",directory:"/project")
    let destination=try await client.sharingDestination(target:target)
    #expect(destination.reportedEndpoint=="https://provider.example")
    #expect(!destination.finalEndpointVerified)
    let encoded=String(decoding:try JSONEncoder().encode(destination),as:UTF8.self)
    #expect(!encoded.contains("private") && !encoded.contains("do-not-persist"))
    await t.setEndpoint("https://different.example/v1")
    #expect(try await client.sharingDestination(target:target).id != destination.id)
  }
  @Test func sharingGuardStopsTextAdmissionBeforeThePost()async throws{
    let t=NativePrivacyTransport(),c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:c,token:"synthetic",transport:t)
    let target=OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_owned",directory:"/project")
    await client.observeSharingAuthorization{_,_,_ in throw RemoteError.forbidden}
    await #expect(throws:OpenCodePromptNotSubmitted(reason:.forbidden)){try await client.send(target:target,input:OpenCodePrompt(text:"Do not dispatch"))}
    #expect(await t.counts()==0)
  }
}
