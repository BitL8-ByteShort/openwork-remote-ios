import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct OpenCodeLiveChatActionTests {
  private struct NewChatFixture:Decodable{
    let pairing:String;let projectID:String;let directory:String;let nonce:String
    let disposable:Bool
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_NEWCHAT_FIXTURE"] != nil),.timeLimit(.minutes(2)))
  func newNativeChatAcceptsARealFreeModelReplyWithoutChangingToolRules()async throws{
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_NEWCHAT_FIXTURE"])
    let fixtureURL=URL(fileURLWithPath:path)
    let f=try JSONDecoder().decode(NewChatFixture.self,from:Data(contentsOf:fixtureURL))
    guard f.disposable,f.nonce.count==32,f.directory.contains("PocketWork Native") else{throw RemoteError.invalidResponse}
    let pair=try OpenCodePairingPayload.parse(f.pairing),origin=try #require(pair.origins.first)
    let token=try await OpenCodePairingClient().redeem(pair,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned new-chat qualification")
    let client=try OpenCodeClient(connection:connection,token:token.token)
    let model=try OpenCodeModelRef(providerID:"opencode",id:"space-bunny-free",variant:"high")
    let intent=try OpenCodeNewChatIntent(connectionID:connection.id,projectID:f.projectID,directory:f.directory,model:model)
    // Preserve the stable intent privately so interrupted qualification can clean up only its chat.
    let intentURL=fixtureURL.appendingPathExtension("created-intent.json")
    guard !FileManager.default.fileExists(atPath:intentURL.path),FileManager.default.createFile(atPath:intentURL.path,contents:try JSONEncoder().encode(intent),attributes:[.posixPermissions:0o600]) else{throw RemoteError.unavailable}
    let created=try await client.createChat(intent)
    #expect(created.id.range(of:"^ses_[0-9a-f]{12}[0-9A-Za-z]{14}$",options:.regularExpression) != nil)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:f.projectID,sessionID:created.id,directory:f.directory)
    let prompt=try OpenCodePrompt(text:"Synthetic connection qualification only. Do not use tools, read files or change anything. Reply exactly: POCKETWORK_NATIVE_NEW_CHAT_OK")
    let admitted=try await client.send(target:target,input:prompt)
    #expect(admitted.matches(prompt,sessionID:created.id))
    let deadline=ContinuousClock.now.advanced(by:.seconds(50))
    var answer:OpenCodeMessage?
    while ContinuousClock.now<deadline{
      let page=try await client.messages(sessionID:created.id,cursor:nil)
      answer=page.data.first{$0.type=="assistant" && $0.time.completed != nil}
      if answer != nil{break}
      try await Task.sleep(for:.milliseconds(500))
    }
    let completed=try #require(answer)
    #expect(!completed.hasError)
    #expect(completed.content.contains{$0.type=="text" && ($0.text?.contains("POCKETWORK_NATIVE_NEW_CHAT_OK") ?? false)})
    #expect(try await client.session(id:created.id).permissions==created.permissions)
    let tree=try await client.sessionTree(target:target)
    guard tree.sessions.count==1,tree.sessions.first?.id==created.id else{throw RemoteError.conflict}
    try await client.deleteSessionTree(tree)
    #expect(try await client.deletedSessionTree(tree))
    print("Owned native new-chat qualification: fresh default ID, real free-model reply, unchanged tool rules and guarded cleanup passed")
  }
  private struct Fixture:Decodable{
    let pairing:String;let projectID:String;let sessionID:String;let directory:String;let nonce:String
    let messageIDs:[String];let createID:String;let treeRootID:String
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_CHAT_ACTIONS_FIXTURE"] != nil))
  func ownedNativeCreateRenameForkBoundaryTreeDeleteAndSearch()async throws{
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_CHAT_ACTIONS_FIXTURE"])
    let f=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let pair=try OpenCodePairingPayload.parse(f.pairing),origin=try #require(pair.origins.first)
    let token=try await OpenCodePairingClient().redeem(pair,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native chat actions")
    let client=try OpenCodeClient(connection:connection,token:token.token)
    let intent=try OpenCodeNewChatIntent(id:f.createID,connectionID:connection.id,projectID:f.projectID,directory:f.directory)
    let created=try await client.createChat(intent)
    #expect(created.id==f.createID)
    #expect(try await client.createdChat(for:intent)?.id==f.createID)
    let createdTarget=OpenCodeTarget(connectionID:connection.id,projectID:f.projectID,sessionID:created.id,directory:f.directory)
    let renamed="PocketWork native renamed "+f.nonce
    #expect(try await client.rename(target:createdTarget,title:renamed,expectedTitle:created.title).title==renamed)
    var page=try await client.sessions(projectID:f.projectID,cursor:nil,search:f.nonce),found=page.data.contains{$0.id==created.id}
    var seen=Set<String>()
    while let next=page.cursor.next,!found{
      #expect(seen.insert(next).inserted);guard seen.count<=30 else{throw RemoteError.oversized}
      page=try await client.sessions(projectID:f.projectID,cursor:next,search:f.nonce);found=page.data.contains{$0.id==created.id}
    }
    #expect(found)
    print("Owned native chat actions: explicit-location stable creation, captured rename and native title search passed")
    let source=OpenCodeTarget(connectionID:connection.id,projectID:f.projectID,sessionID:f.sessionID,directory:f.directory)
    let whole=try await client.fork(target:source,beforeMessageID:nil)
    let partial=try await client.fork(target:source,beforeMessageID:f.messageIDs[10])
    let partialPage=try await client.messages(sessionID:partial.id,cursor:nil)
    #expect(partialPage.data.count==10)
    let texts=partialPage.data.map(\.text)
    #expect(texts.contains("Synthetic native row 9"));#expect(!texts.contains("Synthetic native row 10"))
    var copied=try await client.messages(sessionID:whole.id,cursor:nil),count=copied.data.count
    var cursors=Set<String>()
    while let next=copied.cursor.next{
      #expect(cursors.insert(next).inserted);guard cursors.count<=10 else{throw RemoteError.oversized}
      copied=try await client.messages(sessionID:whole.id,cursor:next);count+=copied.data.count
    }
    #expect(count==205)
    print("Owned native chat actions: whole 205-row fork and exclusive 10-row before-message boundary passed")
    let treeTarget=OpenCodeTarget(connectionID:connection.id,projectID:f.projectID,sessionID:f.treeRootID,directory:f.directory)
    let tree=try await client.sessionTree(target:treeTarget)
    #expect(tree.sessions.count==3)
    try await client.deleteSessionTree(tree)
    #expect(try await client.deletedSessionTree(tree))
    for id in [whole.id,partial.id,created.id]{
      let target=OpenCodeTarget(connectionID:connection.id,projectID:f.projectID,sessionID:id,directory:f.directory)
      let review=try await client.sessionTree(target:target);#expect(review.sessions.count==1)
      try await client.deleteSessionTree(review);#expect(try await client.deletedSessionTree(review))
    }
    print("Owned native chat actions: complete three-chat descendant tree and owned leaf deletes confirmed; no provider execution")
  }
}
