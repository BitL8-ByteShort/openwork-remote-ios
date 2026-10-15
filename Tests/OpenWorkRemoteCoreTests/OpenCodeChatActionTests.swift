import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor NativeChatMutationTransport:HTTPTransport {
  var title="Original"
  var rows:[String:[String:Any]]=[:]
  var creates=0
  var renames=0
  var lostCreate=false
  var lostRename=false
  func loseCreateResponse(){lostCreate=true}
  func loseRenameResponse(){lostRename=true}
  func counts()->(Int,Int){(creates,renames)}
  private func record(_ id:String,marker:String?=nil)->[String:Any]{
    var value:[String:Any]=["id":id,"projectID":"project","title":title,"location":["directory":"/project"],"time":["created":1,"updated":2]]
    if let marker{value["metadata"]=["pocketworkCreationID":marker]};return value
  }
  func data(for request:URLRequest) async throws -> (Data,Int){
    let path=request.url!.path
    if path=="/api/info"{return(Data(#"{"version":"2.0.29","urls":[],"paths":{"tmp":"/tmp/native"}}"#.utf8),200)}
    if path=="/api/location"{return(Data(#"{"directory":"/project","project":{"id":"project","directory":"/project","canonical":"/project"}}"#.utf8),200)}
    if path=="/api/model"{return(Data(#"{"location":{"directory":"/project"},"data":[]}"#.utf8),200)}
    if path=="/api/session",request.httpMethod=="POST"{
      creates+=1;let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      let id=body["id"] as! String,metadata=body["metadata"] as! [String:String]
      let value=record(id,marker:metadata["pocketworkCreationID"]);rows[id]=value
      if lostCreate{throw URLError(.networkConnectionLost)}
      return(try JSONSerialization.data(withJSONObject:["data":value]),200)
    }
    let id=path.split(separator:"/").last.map(String.init) ?? ""
    if request.httpMethod=="PATCH"{
      renames+=1;let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:String];title=body["title"]!
      if lostRename{throw URLError(.networkConnectionLost)}
      return(Data(),204)
    }
    if id=="ses_owned"{return(try JSONSerialization.data(withJSONObject:["data":record(id)]),200)}
    if let value=rows[id]{return(try JSONSerialization.data(withJSONObject:["data":value]),200)}
    return(Data(),404)
  }
}
@Suite struct OpenCodeChatActionTests {
  private func setup(_ transport:NativeChatMutationTransport)throws->(OpenCodeClient,OpenCodeTarget){
    let connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    return(try OpenCodeClient(connection:connection,token:"synthetic",transport:transport),OpenCodeTarget(connectionID:connection.id,projectID:"project",sessionID:"ses_owned",directory:"/project"))
  }
  @Test func renameRejectsBlankAndCapturedDesktopConflictBeforeWriting() async throws{
    let transport=NativeChatMutationTransport(),(client,target)=try setup(transport)
    await #expect(throws:(any Error).self){try await client.rename(target:target,title:"  ",expectedTitle:"Original")}
    await #expect(throws:OpenCodeChatNotSubmitted(reason:.conflict)){try await client.rename(target:target,title:"New",expectedTitle:"Earlier desktop name")}
    #expect(await transport.counts().1==0)
    #expect(try await client.rename(target:target,title:" New ",expectedTitle:"Original").title=="New")
    #expect(await transport.counts().1==1)
  }
  @Test func unavailableLocalDefaultDoesNotFallBackOrCreateAnyChat()async throws{
    let transport=NativeChatMutationTransport(),(client,target)=try setup(transport)
    let intent=try OpenCodeNewChatIntent(connectionID:target.connectionID,projectID:target.projectID,directory:target.directory,
      model:OpenCodeModelRef(providerID:"provider",id:"removed-model"))
    await #expect(throws:OpenCodeChatNotSubmitted(reason:.incompatible)){try await client.createChat(intent)}
    #expect(await transport.counts().0==0)
  }
  @Test func lostRenameAcknowledgementReadsBackWithoutRepeatingPatch()async throws{
    let transport=NativeChatMutationTransport(),(client,target)=try setup(transport)
    await transport.loseRenameResponse()
    #expect(try await client.rename(target:target,title:"Renamed",expectedTitle:"Original").title=="Renamed")
    #expect(try await client.rename(target:target,title:"Renamed",expectedTitle:"Original").title=="Renamed")
    #expect(await transport.counts().1==1)
  }
  @Test func lostCreateResponseReconcilesTheSameStableIDWithoutAnotherPOST() async throws{
    let transport=NativeChatMutationTransport(),(client,target)=try setup(transport)
    let intent=try OpenCodeNewChatIntent(connectionID:target.connectionID,projectID:target.projectID,directory:target.directory)
    await transport.loseCreateResponse()
    let session=try await client.createChat(intent)
    #expect(session.id==intent.id)
    #expect(try await client.createdChat(for:intent)?.id==intent.id)
    #expect(await transport.counts().0==1)
  }
  @Test func newChatUsesTheNativeIdentifierContractRequiredByTheFreeProvider()throws{
    let connection=ConnectionID()
    var ids=Set<String>()
    for _ in 0..<2_000{
      let intent=try OpenCodeNewChatIntent(connectionID:connection,projectID:"project",directory:"/project")
      #expect(intent.id.range(of:"^ses_[0-9a-f]{12}[0-9A-Za-z]{14}$",options:.regularExpression) != nil)
      ids.insert(intent.id)
    }
    #expect(ids.count==2_000)
    let earlier=try OpenCodeNewChatIntent(id:"ses_earlier_stable_intent",connectionID:connection,projectID:"project",directory:"/project")
    let restored=try JSONDecoder().decode(OpenCodeNewChatIntent.self,from:JSONEncoder().encode(earlier))
    #expect(restored.id==earlier.id)
  }
}
