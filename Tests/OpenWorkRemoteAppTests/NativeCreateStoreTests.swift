import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeCreationMemory:NativeCreationPersistence {
  var value=NativeCreationDisk()
  var fails=false
  func fail(){fails=true}
  func load() async throws->NativeCreationDisk{value}
  func save(_ value:NativeCreationDisk,revision:UInt64) async throws{if fails{throw RemoteError.unavailable};self.value=value}
}
private actor NativeCreationService:OpenCodeChatServing {
  var creates=0
  var unknown=false
  var intent:OpenCodeNewChatIntent?
  func makeUnknown(){unknown=true}
  func confirm(){unknown=false}
  func count()->Int{creates}
  private func session(_ intent:OpenCodeNewChatIntent)throws->OpenCodeSession{
    try JSONDecoder().decode(OpenCodeSession.self,from:JSONSerialization.data(withJSONObject:["id":intent.id,"projectID":intent.projectID,"title":"New chat","location":["directory":intent.directory],"time":["created":1,"updated":2]]))
  }
  func createChat(_ intent:OpenCodeNewChatIntent) async throws->OpenCodeSession{creates+=1;self.intent=intent;if unknown{throw RemoteError.outcomeUnknown};return try session(intent)}
  func createdChat(for intent:OpenCodeNewChatIntent) async throws->OpenCodeSession?{unknown ? nil:try session(intent)}
  func rename(target:OpenCodeTarget,title:String,expectedTitle:String?) async throws->OpenCodeSession{throw RemoteError.unavailable}
}
@Suite @MainActor struct NativeCreateStoreTests {
  @Test func failedDurableIntentPreventsAnyCreateRequest() async throws{
    let disk=NativeCreationMemory(),service=NativeCreationService(),store=NativeCreateStore(persistence:disk)
    try await store.restore();store.activate(connectionID:ConnectionID(),client:service)
    await disk.fail()
    #expect(await store.create(projectID:"project",directory:"/project")==nil)
    #expect(await service.count()==0)
    #expect(store.storageIssue)
  }
  @Test func unknownCreateSurvivesRelaunchAndOnlyStatusCheckClearsIt() async throws{
    let disk=NativeCreationMemory(),service=NativeCreationService(),store=NativeCreateStore(persistence:disk),connection=ConnectionID()
    try await store.restore();store.activate(connectionID:connection,client:service);await service.makeUnknown()
    #expect(await store.create(projectID:"project",directory:"/project")==nil)
    #expect(store.pending != nil)
    #expect(await store.create(projectID:"project",directory:"/project")==nil)
    #expect(await service.count()==1)
    let restored=NativeCreateStore(persistence:disk);try await restored.restore();restored.activate(connectionID:connection,client:service)
    #expect(restored.pending?.intent.id==store.pending?.intent.id)
    #expect(await restored.check()==nil)
    await service.confirm()
    #expect(await restored.check() != nil)
    #expect(restored.pending==nil)
    #expect(await service.count()==1)
  }
}
