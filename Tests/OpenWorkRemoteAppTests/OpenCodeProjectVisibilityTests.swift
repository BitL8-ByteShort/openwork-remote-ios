import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor MemoryVisibilityPersistence:NativeVisibilityPersistence {
  var value=NativeVisibilitySnapshot()
  var fail=false
  func setFailure(){fail=true}
  func load() async throws -> NativeVisibilitySnapshot {value}
  func save(_ value:NativeVisibilitySnapshot,revision:UInt64) async throws {
    if fail {throw RemoteError.unavailable};self.value=value
  }
}
@Suite @MainActor struct OpenCodeProjectVisibilityTests {
  @Test func newProjectsCanBeHiddenWithoutChangingPreviouslyShownProjects() {
    var policy=NativeProjectVisibility()
    policy.observe(["existing"]);policy.showNewProjects=false;policy.observe(["existing","new"])
    #expect(policy.shows("existing"));#expect(!policy.shows("new"))
    policy.setShown("new",shown:true)
    #expect(policy.shows("new"))
    policy.setShown("existing",shown:false);policy.showNewProjects=true
    #expect(!policy.shows("existing"));#expect(policy.shows("future"))
  }
  @Test func visibilityIsScopedByConnectionIdentity() async throws {
    let store=NativeProjectVisibilityStore(persistence:MemoryVisibilityPersistence())
    try await store.restore()
    let a=ConnectionID(),b=ConnectionID()
    store.activate(a);try await store.observe(["same-project"]);try await store.setShown("same-project",shown:false)
    store.activate(b);try await store.observe(["same-project"])
    #expect(store.policy.shows("same-project"))
    store.activate(a);#expect(!store.policy.shows("same-project"))
  }
  @Test func aFailedSaveKeepsTheActualVisibleState() async throws {
    let persistence=MemoryVisibilityPersistence(),store=NativeProjectVisibilityStore(persistence:MemoryVisibilityPersistence())
    let failing=NativeProjectVisibilityStore(persistence:persistence)
    try await failing.restore();failing.activate(ConnectionID());try await failing.observe(["project"])
    await persistence.setFailure()
    await #expect(throws:RemoteError.unavailable) {try await failing.setShown("project",shown:false)}
    #expect(failing.policy.shows("project"))
    #expect(!store.ready)
  }
  @Test func aProtectedDiskSnapshotCanBeReloadedWithoutAServer() async throws {
    let folder=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:folder)}
    let id=ConnectionID()
    let first=NativeProjectVisibilityStore(persistence:try NativeVisibilityFile(directory:folder))
    try await first.restore();first.activate(id);try await first.observe(["one"]);try await first.setShowNewProjects(false)
    let second=NativeProjectVisibilityStore(persistence:try NativeVisibilityFile(directory:folder))
    try await second.restore();second.activate(id);try await second.observe(["one","two"])
    #expect(second.policy.shows("one"));#expect(!second.policy.shows("two"))
  }
  @Test func anOversizedSnapshotCannotBeWrittenThenFailItsOwnReloadLimit() async throws {
    let folder=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:folder)}
    let file=try NativeVisibilityFile(directory:folder)
    var policy=NativeProjectVisibility(),snapshot=NativeVisibilitySnapshot()
    policy.observe(Set((0..<3_000).map{String(repeating:"x",count:1_990)+String($0)}))
    snapshot.connections[UUID().uuidString.lowercased()]=policy
    await #expect(throws:RemoteError.oversized){try await file.save(snapshot,revision:1)}
  }
  @Test func aFutureSchemaDoesNotLookLikeEmptyPreferences() async throws {
    let folder=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:folder)}
    let file=try NativeVisibilityFile(directory:folder)
    try Data(#"{"schemaVersion":99,"connections":{}}"#.utf8).write(to:folder.appending(path:"project-visibility.json"))
    let store=NativeProjectVisibilityStore(persistence:file)
    await #expect(throws:RemoteError.incompatible){try await store.restore()}
    #expect(!store.ready);#expect(store.lastError != nil)
  }
}
