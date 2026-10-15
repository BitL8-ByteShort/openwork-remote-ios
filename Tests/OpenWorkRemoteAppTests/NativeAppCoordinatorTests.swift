import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor NativeShellTransport:HTTPTransport {
  var paths:[String]=[]
  var held:CheckedContinuation<Void,Never>?
  var waiters:[CheckedContinuation<Void,Never>]=[]
  var catalogReads=0
  var holdFirstHistory=true
  var admitted:[String:Any]?
  var prompts=0
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
      if holdFirstHistory{holdFirstHistory=false;await withCheckedContinuation{c in held=c;waiters.forEach{$0.resume()};waiters=[]}}
      value=["data":[["id":"msg_owned","type":"user","text":"Native message","time":["created":1]]],"cursor":[:]]
    case "/api/session/ses_owned/prompt":
      prompts+=1;let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      let payload:[String:Any]=["id":body["id"]!,"sessionID":"ses_owned","type":"user","payload":["text":body["text"]!]]
      admitted=payload;value=["data":payload]
    case "/api/session/ses_owned/inbox":value=["data":admitted.map{[$0]} ?? []]
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
  func sentPrompts()->Int{prompts}
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
    app.jumpToLatest()
    #expect(app.messages.first?.blocks.first?.text=="Newer message")
    #expect(!app.navigation.hasNewReplies)
    #expect(app.navigation.olderCursor=="opaque-latest")
    #expect(await transport.modelReads()==0)
    #expect(await transport.calledPaths().allSatisfy{$0.hasPrefix("/api/")})
  }
}

@Suite @MainActor struct NativeAppModelFacadeTests {
  @Test(.timeLimit(.minutes(1))) func nativeLaunchNeverContactsLegacyPairingAndKeepsItsDraftSeparate() async throws {
    let directory=FileManager.default.temporaryDirectory.appending(path:"native-facade-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:directory)}
    let legacy=try DraftStore(directory:directory)
    var old=DiskState();let key=DraftKey(hostId:"legacy-host",workspaceId:"project",sessionId:"ses_owned")
    old.conversation.select(key);old.conversation.setDraft("Earlier OpenWork text")
    try await legacy.save(old,revision:1)
    let c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Native computer")
    let saved=StoredOpenCodeConnection(connection:c,token:"synthetic-token"),transport=NativeShellTransport()
    let native=try NativeAppCoordinator(directory:directory,connectionPersistence:OpenCodePersistence(load:{saved},save:{_ in},remove:{}),transport:transport)
    defer{native.deactivate()}
    let pairing=StoredPairing(origin:"https://legacy.invalid",token:"synthetic-legacy-token",hostId:"legacy-host")
    let model=AppModel(native:native,legacyDraftStore:legacy,pairingPersistence:PairingPersistence(load:{pairing},save:{_ in},remove:{}),transport:transport)
    await model.start()
    #expect(model.connection == .ready);#expect(model.host==nil)
    #expect(model.serviceName=="OpenCode")
    #expect(model.computerName=="Native computer")
    #expect(model.connectionLabel=="Connected")
    #expect(model.workspaces.map(\.name)==["Native project"])
    #expect(model.nativeMigration?.recoverableText=="Earlier OpenWork text")
    let session=try #require(model.sessions.first)
    let opening=Task{await model.select(session)};await transport.waitForHeldHistory()
    #expect(model.selectedSession?.id==session.id)
    await transport.releaseHistory();await opening.value
    #expect(model.messages.first?.blocks.first?.text=="Native message")
    #expect(model.draft.isEmpty)
    model.draft="New native text";#expect(model.draft=="New native text");#expect(model.canSend)
    await model.send();#expect(model.draft.isEmpty)
    #expect(await transport.sentPrompts()==1)
    #expect(try await legacy.load().conversation.draft(for:key)=="Earlier OpenWork text")
    await model.forget()
    #expect(model.connection == .unpaired)
    #expect(model.sessions.isEmpty);#expect(model.messages.isEmpty);#expect(model.selectedSession==nil)
    #expect(try await legacy.load().conversation.draft(for:key)=="Earlier OpenWork text")
    #expect(await transport.calledPaths().allSatisfy{$0.hasPrefix("/api/")})
  }
}
