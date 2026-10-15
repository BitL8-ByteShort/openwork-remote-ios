import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct NativeSelectionTests {
  @Test func protectedStorageFailureIsNotMistakenForAnUnpairedInstallAndCanRetry()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-storage-retry-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    _ = try DraftStore(directory:root)
    let corrupt=root.appending(path:"native-selection.json");try Data("invalid snapshot".utf8).write(to:corrupt)
    let saved=try nativeStored(),transport=NativeShellTransport();await transport.allowHistory()
    let app=try NativeAppCoordinator(directory:root,connectionPersistence:OpenCodePersistence(load:{saved},save:{_ in},remove:{}),transport:transport)
    defer{app.deactivate()}
    await #expect(throws:(any Error).self){try await app.start()}
    #expect(!app.ready && app.startupState == .storageUnavailable)
    #expect(await transport.calledPaths().isEmpty)
    try FileManager.default.removeItem(at:corrupt);try await app.start()
    #expect(app.ready && app.startupState == .ready && app.connection.state == .ready)
  }
  @Test func foregroundUsesFreshCredentialsAndRestoresSelectionWithoutSending()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-foreground-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let saved=try nativeStored(),transport=NativeShellTransport();await transport.allowHistory()
    let app=try NativeAppCoordinator(directory:root,connectionPersistence:OpenCodePersistence(load:{saved},save:{_ in},remove:{}),transport:transport)
    defer{app.deactivate()};try await app.start();await app.open(try #require(app.navigation.sessions.first))
    let target=try #require(app.navigation.target),old=try #require(app.connection.client)
    try await app.journal.saveDraft("Unsent",for:target)
    await app.sceneActive(false);#expect(app.conversation.target==nil)
    await app.sceneActive(true)
    #expect(app.connection.client !== old && app.navigation.target==target)
    #expect(app.draft=="Unsent" && app.canSend)
    #expect(await transport.sentPrompts()==0)
    await app.sceneActive(false);await transport.setInfoStatus(401);await app.sceneActive(true)
    #expect(app.connection.state == .authenticationRejected && !app.canSend)
    #expect(app.journal.draft(for:target)=="Unsent")
  }
  @Test func relaunchAndReconnectRestoreTheVerifiedChatAndItsDraft()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-selection-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let saved=try nativeStored(),transport=NativeShellTransport();await transport.allowHistory()
    let persistence=OpenCodePersistence(load:{saved},save:{_ in},remove:{})
    let first=try NativeAppCoordinator(directory:root,connectionPersistence:persistence,transport:transport)
    try await first.start();await first.open(try #require(first.navigation.sessions.first))
    let target=try #require(first.navigation.target)
    try await first.journal.saveDraft("Local unfinished text",for:target)
    first.deactivate()
    let second=try NativeAppCoordinator(directory:root,connectionPersistence:persistence,transport:transport)
    defer{second.deactivate()};try await second.start()
    #expect(second.navigation.target==target)
    #expect(second.draft=="Local unfinished text")
    await second.reconnect()
    #expect(second.navigation.target==target && second.draft=="Local unfinished text")
    #expect(await transport.sentPrompts()==0)
  }
  @Test func changedAuthoritativeDirectoryCannotClaimTheSavedChatOrDraft()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-moved-selection-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let saved=try nativeStored(),transport=NativeShellTransport();await transport.allowHistory()
    let persistence=OpenCodePersistence(load:{saved},save:{_ in},remove:{})
    let first=try NativeAppCoordinator(directory:root,connectionPersistence:persistence,transport:transport)
    try await first.start();await first.open(try #require(first.navigation.sessions.first))
    let target=try #require(first.navigation.target);try await first.journal.saveDraft("Old folder",for:target);first.deactivate()
    await transport.moveSession(to:"/moved")
    let second=try NativeAppCoordinator(directory:root,connectionPersistence:persistence,transport:transport)
    defer{second.deactivate()};try await second.start()
    #expect(second.navigation.target==nil && second.draft.isEmpty)
    #expect(second.journal.draft(for:target)=="Old folder")
    #expect(second.notice?.contains("moved")==true)
    await second.open(try #require(second.navigation.sessions.first))
    #expect(second.navigation.target?.directory=="/moved" && second.draft.isEmpty)
  }
}
