import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor NativeShellTransport:HTTPTransport {
  var paths:[String]=[]
  var held:CheckedContinuation<Void,Never>?
  var waiters:[CheckedContinuation<Void,Never>]=[]
  var catalogReads=0
  let session:[String:String]=["id":"ses_owned","projectID":"project","title":"Native chat"]
  func data(for request:URLRequest) async throws -> (Data,Int){
    let path=request.url!.path;paths.append(path)
    let record:[String:Any]=["id":"ses_owned","projectID":"project","title":"Native chat","location":["directory":"/project"],"time":["created":1,"updated":2]]
    let value:Any
    switch path{
    case "/api/info":value=["version":"2.0.29","urls":[],"paths":["tmp":"/tmp/native"]]
    case "/api/project":value=[["id":"project","name":"Native project","canonical":"/project","sandboxes":[],"time":["created":1,"updated":2,"active":2]]]
    case "/api/session":value=["data":[record],"cursor":[:]]
    case "/api/session/ses_owned":value=["data":record]
    case "/api/session/ses_owned/message":
      await withCheckedContinuation{c in held=c;waiters.forEach{$0.resume()};waiters=[]}
      value=["data":[["id":"msg_owned","type":"user","text":"Native message","time":["created":1]]],"cursor":[:]]
    case "/api/session/ses_owned/inbox":value=["data":[]]
    case "/api/session/active":value=["data":[:]]
    case "/api/session/ses_owned/permission":value=["data":[["id":"per_owned","sessionID":"ses_owned","action":"read","resources":["notes.txt"]]]]
    case "/api/session/ses_owned/form":value=["data":[["id":"frm_owned","sessionID":"ses_owned","title":"Choose","fields":[["key":"answer","type":"string","required":true]]]]]
    case "/api/model":catalogReads+=1;throw RemoteError.unavailable
    default:throw RemoteError.invalidResponse
    }
    return(try JSONSerialization.data(withJSONObject:value),200)
  }
  func events(for request:URLRequest) async throws -> AsyncThrowingStream<SSEFrame,any Error>{paths.append(request.url!.path);return AsyncThrowingStream{_ in}}
  func waitForHeldHistory() async{if held != nil{return};await withCheckedContinuation{waiters.append($0)}}
  func releaseHistory(){held?.resume();held=nil}
  func calledPaths()->[String]{paths}
  func modelReads()->Int{catalogReads}
}
@Suite @MainActor struct NativeAppCoordinatorTests {
  @Test(.timeLimit(.minutes(1))) func nativeCompositionShowsInputsWhileHistoryAndCatalogAreUnavailable() async throws {
    let directory=FileManager.default.temporaryDirectory.appending(path:"native-app-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:directory)}
    let connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Native computer")
    let saved=StoredOpenCodeConnection(connection:connection,token:"synthetic-token")
    let transport=NativeShellTransport()
    let app=try NativeAppCoordinator(directory:directory,connectionPersistence:OpenCodePersistence(load:{saved},save:{_ in},remove:{}),transport:transport)
    defer{app.deactivate()}
    try await app.start()
    let chat=try #require(app.navigation.sessions.first)
    let opening=Task{await app.open(chat)};await transport.waitForHeldHistory()
    #expect(app.navigation.selectedSession?.id==chat.id)
    let deadline=ContinuousClock.now.advanced(by:.seconds(3))
    while (app.approvals.requests.isEmpty || app.forms.pending.isEmpty),ContinuousClock.now<deadline{try await Task.sleep(for:.milliseconds(10))}
    let approvalsVisible=app.approvals.requests.count==1,formsVisible=app.forms.pending.count==1
    await transport.releaseHistory();await opening.value
    #expect(approvalsVisible);#expect(formsVisible)
    #expect(app.messages.first?.blocks.first?.text=="Native message")
    let target=try #require(app.navigation.target)
    let page=try JSONDecoder().decode(OpenCodeMessagePage.self,from:Data(#"{"data":[{"id":"msg_new","type":"user","text":"Newer message","time":{"created":3}}],"cursor":{"next":"opaque-latest"}}"#.utf8))
    app.navigation.acceptNativeSnapshot(target:target,session:chat,page:page,preserveWindow:true)
    #expect(app.messages.first?.blocks.first?.text=="Native message")
    #expect(app.navigation.hasNewReplies)
    app.navigation.acceptNativeSnapshot(target:target,session:chat,page:page,preserveWindow:false)
    #expect(app.messages.first?.blocks.first?.text=="Newer message")
    #expect(!app.navigation.hasNewReplies)
    #expect(await transport.modelReads()==0)
    #expect(await transport.calledPaths().allSatisfy{$0.hasPrefix("/api/")})
  }
}
