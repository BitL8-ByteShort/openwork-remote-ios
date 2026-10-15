import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct LocalChatGroupTests {
  @Test func orderedLocalGroupsPersistAndRemovalOnlyUnassignsChats()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let store=LocalChatGroupStore(persistence:try LocalChatGroupFile(directory:root))
    try await store.restore()
    let scope=NativeProjectKey(connectionID:ConnectionID(),projectID:"project")
    store.activate(scope)
    try await store.change(.create("Work"),scope:scope,expectedRevision:0)
    let group=try #require(store.snapshot.groups.first)
    try await store.change(.assign(sessionID:"ses_one",groupID:group.id),scope:scope,expectedRevision:1)
    await #expect(throws:RemoteError.conflict){try await store.change(.rename(group.id,"Stale"),scope:scope,expectedRevision:1)}
    try await store.change(.rename(group.id,"New name"),scope:scope,expectedRevision:2)
    let restored=LocalChatGroupStore(persistence:try LocalChatGroupFile(directory:root));try await restored.restore();restored.activate(scope)
    #expect(restored.snapshot.groups.first?.label=="New name")
    #expect(restored.snapshot.assignments["ses_one"]==group.id)
    try await restored.change(.remove(group.id),scope:scope,expectedRevision:3)
    #expect(restored.snapshot.groups.isEmpty && restored.snapshot.assignments.isEmpty)
    restored.activate(NativeProjectKey(connectionID:ConnectionID(),projectID:"project"))
    #expect(restored.snapshot.revision==0)
    #expect(store.snapshot.assignments["ses_one"]==group.id)
  }
}
