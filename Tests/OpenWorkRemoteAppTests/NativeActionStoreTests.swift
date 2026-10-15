import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeActionMemory:NativeActionPersistence {
  var disk=NativeActionDisk()
  func load()async throws->NativeActionDisk{disk}
  func save(_ value:NativeActionDisk,revision:UInt64)async throws{disk=value}
}
private actor NativeActionService:OpenCodeTreeServing {
  var calls=0
  func count()->Int{calls}
  func fork(target:OpenCodeTarget,beforeMessageID:String?)async throws->OpenCodeSession{calls+=1;throw RemoteError.outcomeUnknown}
  func sessionTree(target:OpenCodeTarget)async throws->OpenCodeSessionTree{throw RemoteError.unavailable}
  func deleteSessionTree(_ review:OpenCodeSessionTree)async throws{throw RemoteError.unavailable}
  func deletedSessionTree(_ review:OpenCodeSessionTree)async throws->Bool{false}
}
@Suite @MainActor struct NativeActionStoreTests {
  @Test func unknownForkSurvivesRelaunchAndCannotBeRepeatedOrClearedWithoutReview()async throws{
    let disk=NativeActionMemory(),service=NativeActionService(),connection=ConnectionID()
    let target=OpenCodeTarget(connectionID:connection,projectID:"project",sessionID:"ses_owned",directory:"/project")
    let store=NativeChatActionStore(persistence:disk);try await store.restore();store.activate(target:target,client:service)
    #expect(await store.perform(.fork(beforeMessageID:"msg_boundary"))==nil)
    #expect(store.pending?.state == .unknown)
    let restored=NativeChatActionStore(persistence:disk);try await restored.restore();restored.activate(target:target,client:service)
    #expect(restored.pending?.id==store.pending?.id)
    #expect(await restored.perform(.fork(beforeMessageID:nil))==nil)
    await #expect(throws:(any Error).self){try await restored.keepCurrentChats()}
    restored.markReviewed()
    try await restored.keepCurrentChats()
    #expect(restored.pending==nil)
    #expect(await service.count()==1)
  }
}
