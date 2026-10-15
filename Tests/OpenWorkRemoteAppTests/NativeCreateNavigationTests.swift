import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeCreateNavigationTransport:HTTPTransport {
  var held:CheckedContinuation<Void,Never>?
  var waiters:[CheckedContinuation<Void,Never>]=[]
  var created:[String:Any]?
  func waitForCreate()async{if held != nil{return};await withCheckedContinuation{waiters.append($0)}}
  func release(){held?.resume();held=nil}
  func data(for r:URLRequest)async throws->(Data,Int){
    let path=r.url!.path,value:Any
    if path=="/api/info"{value=["version":"2.0.29","urls":[],"paths":["tmp":"/tmp/native"]]}
    else if path=="/api/project"{value=[["id":"project","canonical":"/project","sandboxes":[],"time":["created":1,"updated":2,"active":2]]]}
    else if path=="/api/location"{value=["directory":"/project","project":["id":"project","directory":"/project","canonical":"/project"]]}
    else if path=="/api/session",r.httpMethod=="POST"{
      let body=try JSONSerialization.jsonObject(with:r.httpBody!) as! [String:Any]
      let row:[String:Any]=["id":body["id"]!,"projectID":"project","title":"New chat","metadata":body["metadata"]!,"location":["directory":"/project"],"time":["created":1,"updated":2]]
      await withCheckedContinuation{held=$0;waiters.forEach{$0.resume()};waiters=[]}
      created=row;value=["data":row]
    }else if path=="/api/session"{value=["data":created.map{[$0]} ?? [],"cursor":[:]]}
    else if path.hasSuffix("/message"){value=["data":[],"cursor":[:]]}
    else if path.hasSuffix("/inbox") || path.hasSuffix("/form") || path.hasSuffix("/permission"){value=["data":[]]}
    else if path=="/api/session/active"{value=["data":[:]]}
    else if let created,path=="/api/session/"+(created["id"] as! String){value=["data":created]}
    else{return(Data(),404)}
    return(try JSONSerialization.data(withJSONObject:value),200)
  }
  func events(for r:URLRequest)async throws->AsyncThrowingStream<SSEFrame,any Error>{AsyncThrowingStream{_ in}}
}
@Suite @MainActor struct NativeCreateNavigationTests {
  @Test(.timeLimit(.minutes(1))) func lateCreationDoesNotStealAChangedSelectionInTheSameProject()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let stored=StoredOpenCodeConnection(connection:c,token:"synthetic"),transport=NativeCreateNavigationTransport()
    let app=try NativeAppCoordinator(directory:root,connectionPersistence:OpenCodePersistence(load:{stored},save:{_ in},remove:{}),transport:transport)
    defer{app.deactivate()}
    try await app.start()
    let creation=Task{await app.createChat()};await transport.waitForCreate()
    let project=try #require(app.workspaces.first)
    await app.changeWorkspace(project);await transport.release();_=await creation.value
    #expect(app.navigation.selectedSession==nil)
    #expect(app.navigation.sessions.count==1)
    #expect(app.creation.pending==nil)
    let chat=try #require(app.navigation.sessions.first),generation=app.selectionGeneration
    await app.changeWorkspace(project)
    let source=OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_original",directory:"/project")
    await app.completeAction(.fork(chat),request:source,deletedIDs:[],generation:generation)
    #expect(app.navigation.selectedSession==nil)
    #expect(app.navigation.sessions.contains{$0.id==chat.id})
  }
}
