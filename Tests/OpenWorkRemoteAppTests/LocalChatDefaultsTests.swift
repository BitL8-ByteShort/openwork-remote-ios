import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct LocalChatDefaultsTests {
  @Test func defaultsAreLocalScopedPersistentAndExplicitlyClearable()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let store=LocalChatDefaultsStore(persistence:try LocalChatDefaultsFile(directory:root))
    try await store.restore()
    let scope=NativeProjectKey(connectionID:ConnectionID(),projectID:"project")
    store.activate(scope)
    let value=LocalChatDefaults(model:try OpenCodeModelRef(providerID:"provider",id:"model",variant:"high"),agent:"build")
    try await store.set(value,scope:scope,expected:LocalChatDefaults())
    #expect(store.value==value)
    let restored=LocalChatDefaultsStore(persistence:try LocalChatDefaultsFile(directory:root));try await restored.restore();restored.activate(scope)
    #expect(restored.value==value)
    await #expect(throws:RemoteError.conflict){try await restored.set(LocalChatDefaults(),scope:scope,expected:LocalChatDefaults())}
    try await restored.set(LocalChatDefaults(),scope:scope,expected:value)
    #expect(restored.value.model==nil && restored.value.agent==nil)
    restored.activate(NativeProjectKey(connectionID:ConnectionID(),projectID:"project"))
    #expect(restored.value==LocalChatDefaults())
  }
}
