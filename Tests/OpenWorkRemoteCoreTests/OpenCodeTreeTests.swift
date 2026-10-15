import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor NativeTreeTransport:HTTPTransport {
  var deleted=false
  var addChild=false
  var escape=false
  var lostFork=false
  var forkBodies:[[String:String]]=[]
  var deletes=0
  func changed(){addChild=true}
  func escaping(){escape=true}
  func loseFork(){lostFork=true}
  func counts()->(Int,[[String:String]]){(deletes,forkBodies)}
  private func row(_ id:String,parent:String?=nil)->[String:Any]{
    var value:[String:Any]=["id":id,"projectID":"project","title":id,"location":["directory":escape && parent != nil ? "/elsewhere":"/project"],"time":["created":1,"updated":2]]
    if let parent{value["parentID"]=parent};return value
  }
  func data(for r:URLRequest)async throws->(Data,Int){
    let path=r.url!.path
    if path=="/api/info"{return(Data(#"{"version":"2.0.29","urls":[],"paths":{"tmp":"/tmp/native"}}"#.utf8),200)}
    if path=="/api/session/active"{return(Data(#"{"data":{}}"#.utf8),200)}
    if path=="/api/session/ses_root/fork"{
      forkBodies.append(try JSONSerialization.jsonObject(with:r.httpBody!) as! [String:String])
      if lostFork{throw URLError(.networkConnectionLost)}
      return(try JSONSerialization.data(withJSONObject:["data":row("ses_fork")]),200)
    }
    if path=="/api/session"{
      let parent=URLComponents(url:r.url!,resolvingAgainstBaseURL:false)!.queryItems?.first(where:{$0.name=="parentID"})?.value
      var rows:[[String:Any]]=[]
      if parent=="ses_root"{rows=[row("ses_child",parent:"ses_root")];if addChild{rows.append(row("ses_new",parent:"ses_root"))}}
      return(try JSONSerialization.data(withJSONObject:["data":deleted ? []:rows,"cursor":[:]]),200)
    }
    if r.httpMethod=="DELETE"{deletes+=1;deleted=true;return(Data(),204)}
    if deleted{return(Data(),404)}
    return(try JSONSerialization.data(withJSONObject:["data":row(path.split(separator:"/").last.map(String.init)!)]),200)
  }
}
@Suite struct OpenCodeTreeTests {
  private func setup(_ t:NativeTreeTransport)throws->(OpenCodeClient,OpenCodeTarget){
    let c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    return(try OpenCodeClient(connection:c,token:"synthetic",transport:t),OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_root",directory:"/project"))
  }
  @Test func treeIncludesChildrenAndRechecksBeforeOneDelete()async throws{
    let t=NativeTreeTransport(),(client,target)=try setup(t)
    let review=try await client.sessionTree(target:target)
    #expect(review.sessions.map(\.id)==["ses_root","ses_child"])
    await t.changed()
    await #expect(throws:OpenCodeChatNotSubmitted(reason:.conflict)){try await client.deleteSessionTree(review)}
    #expect(await t.counts().0==0)
    let fresh=try await client.sessionTree(target:target)
    try await client.deleteSessionTree(fresh)
    #expect(await t.counts().0==1)
    #expect(try await client.deletedSessionTree(fresh))
  }
  @Test func outsideLocationChildFailsClosedAndForkUsesExactExclusiveBoundary()async throws{
    let t=NativeTreeTransport(),(client,target)=try setup(t)
    #expect(try await client.fork(target:target,beforeMessageID:"msg_boundary").id=="ses_fork")
    #expect(await t.counts().1==[["before":"msg_boundary"]])
    await t.loseFork()
    await #expect(throws:RemoteError.outcomeUnknown){try await client.fork(target:target,beforeMessageID:nil)}
    #expect(await t.counts().1==[["before":"msg_boundary"],[:]])
    await t.escaping()
    await #expect(throws:RemoteError.conflict){try await client.sessionTree(target:target)}
    #expect(await t.counts().0==0)
  }
}
