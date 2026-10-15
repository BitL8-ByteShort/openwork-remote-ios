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
}
