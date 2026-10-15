import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct OpenCodeResetTests{
  @Test func registeredSnapshotActorsAreRetiredBeforeRemovalAndCannotRecreateTheirFiles()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-snapshot-reset-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let files=try NativeLocalDataFiles(directory:root)
    try await files.conversations.save(NativeConversationDisk(),revision:1)
    try await files.forms.save(NativeFormDisk(),revision:1)
    try await files.visibility.save(NativeVisibilitySnapshot(),revision:1)
    try await files.creation.save(NativeCreationDisk(),revision:1)
    try await files.actions.save(NativeActionDisk(),revision:1)
    try await files.groups.save(LocalChatGroupDisk(),revision:1)
    try await files.defaults.save(LocalChatDefaultsDisk(),revision:1)
    try await files.selection.save(NativeSelectionDisk(),revision:1)
    try await files.sharing.save(ProviderDisclosureDisk(),revision:1)
    await files.retireWriters()
    #expect(FileManager.default.fileExists(atPath:root.appending(path:"native-conversations.json").path))
    await #expect(throws:SnapshotStoreError.self){try await files.conversations.save(NativeConversationDisk(),revision:20)}
    #expect(await files.removeAll().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
    await #expect(throws:SnapshotStoreError.self){try await files.sharing.save(ProviderDisclosureDisk(),revision:20)}
    await #expect(throws:SnapshotStoreError.self){try await files.selection.save(NativeSelectionDisk(),revision:20)}
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
  }
  @Test func clearDraftsCoversBothBackendsAndPreservesBothUncertainSendIDs()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-clear-drafts-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let legacy=try DraftStore(directory:root),saved=NativeSavedConnection(try nativeStored()),transport=NativeShellTransport()
    var disk=DiskState();disk.conversation.select(DraftKey(hostId:"old",workspaceId:"project",sessionId:"ses_old"));disk.conversation.setDraft("Earlier uncertain text")
    let legacyIntent=try disk.conversation.beginSend(ready:true);disk.conversation.applyReceipt(legacyIntent,accepted:false)
    try await legacy.save(disk,revision:100)
    let native=try NativeAppCoordinator(directory:root,connectionPersistence:saved.persistence,transport:transport)
    let model=AppModel(native:native,legacyDraftStore:legacy,pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{}))
    await model.start()
    let target=OpenCodeTarget(connectionID:try #require(saved.value?.connection.id),projectID:"project",sessionID:"ses_owned",directory:"/project")
    try await native.journal.saveDraft("Native uncertain text",for:target)
    let nativeIntent=try await native.journal.prepare(target:target)
    #expect(await model.clearLocalDrafts())
    let old=try await legacy.load()
    #expect(old.conversation.currentDraft.isEmpty && old.conversation.pendingRequestId(for:legacyIntent.key)==legacyIntent.requestId)
    #expect(native.journal.draft(for:target).isEmpty && native.journal.pending(for:target)?.prompt.id==nativeIntent.prompt.id)
    #expect(native.journal.pending(for:target)?.prompt.text=="Native uncertain text")
    #expect(saved.value != nil)
    #expect(await transport.sentPrompts()==0)
    native.deactivate()
  }
  @Test func resetReportsAnUnknownDownloadWithoutDeletingIt()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-reset-partial-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let legacy=try DraftStore(directory:root),saved=NativeSavedConnection(try nativeStored()),transport=NativeShellTransport()
    let native=try NativeAppCoordinator(directory:root,connectionPersistence:saved.persistence,transport:transport)
    let model=AppModel(native:native,legacyDraftStore:legacy,pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{}))
    await model.start()
    let folder=root.appending(path:"NativeDownloads");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let unknown=folder.appending(path:"unrecognized.txt");try Data("Keep".utf8).write(to:unknown)
    let report=try #require(await model.resetLocalData())
    #expect(report.credentialsRemoved && report.localFailures.contains("OpenCode downloaded and preview copies"))
    #expect(FileManager.default.fileExists(atPath:unknown.path))
  }
  @Test(.timeLimit(.minutes(1))) func aLateAdmittedPromptCannotRecreateResetDataOrEnterTheFreshApp()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-reset-pending-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let legacy=try DraftStore(directory:root),saved=NativeSavedConnection(try nativeStored()),transport=NativeShellTransport()
    await transport.allowHistory();await transport.enablePrivacyCatalog()
    let native=try NativeAppCoordinator(directory:root,connectionPersistence:saved.persistence,transport:transport)
    let model=AppModel(native:native,legacyDraftStore:legacy,pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{}))
    await model.start();await model.select(try #require(model.sessions.first));model.draft="Captured old send"
    await model.send()
    #expect(await native.sharing.approve(try #require(native.sharing.review),using:try #require(native.connection.client),acknowledgesUnknownDestination:true))
    await transport.holdNextPrompt();let sending=Task{await model.send()}
    while !(await transport.promptIsHeld()){await Task.yield()}
    let report=try #require(await model.resetLocalData()),fresh=try model.freshAfterReset(report)
    await fresh.start();await transport.releasePrompt();await sending.value
    #expect(report.localFailures.isEmpty)
    #expect(fresh.connection == .unpaired && fresh.native?.journal.recoverableDrafts.isEmpty==true)
    #expect(!FileManager.default.fileExists(atPath:root.appending(path:"native-conversations.json").path))
    #expect(!FileManager.default.fileExists(atPath:root.appending(path:"native-sharing-consent.json").path))
    #expect(await transport.sentPrompts()==1)
  }
  @Test func resetRemovesBothCredentialNamespacesAndNativeSnapshotsWithoutHostWrites()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-reset-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let legacy=try DraftStore(directory:root),saved=NativeSavedConnection(try nativeStored()),transport=NativeShellTransport()
    var legacyCredential:StoredPairing?=StoredPairing(origin:"https://old.invalid",token:"synthetic-old",hostId:"old")
    let pairing=PairingPersistence(load:{legacyCredential},save:{legacyCredential=$0},remove:{legacyCredential=nil})
    var old=DiskState();old.conversation.select(DraftKey(hostId:"old",workspaceId:"project",sessionId:"ses_old"));old.conversation.setDraft("Old unsent text")
    try await legacy.save(old,revision:1)
    let native=try NativeAppCoordinator(directory:root,connectionPersistence:saved.persistence,transport:transport)
    let model=AppModel(native:native,legacyDraftStore:legacy,pairingPersistence:pairing)
    await model.start()
    let scope=try #require(native.projectKey)
    try await native.groups.change(.create("Device group"),scope:scope,expectedRevision:0)
    try await native.defaults.set(LocalChatDefaults(agent:"build"),scope:scope,expected:LocalChatDefaults())
    let target=OpenCodeTarget(connectionID:try #require(saved.value?.connection.id),projectID:"project",sessionID:"ses_owned",directory:"/project")
    try await native.journal.saveDraft("Native unsent text",for:target)
    let sentinel=root.appending(path:"unrelated.txt");try Data("Keep".utf8).write(to:sentinel)
    let report=try #require(await model.resetLocalData())
    #expect(saved.value==nil && legacyCredential==nil)
    #expect(report.localFailures.isEmpty && report.hostRevocation == .nativeNotRevoked)
    #expect(report.summary.contains("not revoked"))
    #expect(!FileManager.default.fileExists(atPath:root.appending(path:"native-conversations.json").path))
    #expect(!FileManager.default.fileExists(atPath:root.appending(path:"drafts.json").path))
    #expect(!FileManager.default.fileExists(atPath:root.appending(path:"native-local-groups.json").path))
    #expect(!FileManager.default.fileExists(atPath:root.appending(path:"native-local-defaults.json").path))
    #expect(FileManager.default.fileExists(atPath:sentinel.path))
    await #expect(throws:(any Error).self){try await native.journal.saveDraft("Late",for:target)}
    let fresh=try model.freshAfterReset(report);await fresh.start()
    #expect(fresh.native != nil && fresh.connection == .unpaired && fresh.native?.journal.recoverableDrafts.isEmpty==true)
    #expect(await transport.calledPaths().allSatisfy{!$0.contains("revoke")})
    #expect(await transport.sentPrompts()==0)
  }
  @Test func credentialRemovalFailureStopsRequestsAndKeepsLocalFilesForRetry()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-reset-locked-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let legacy=try DraftStore(directory:root),saved=NativeSavedConnection(try nativeStored()),transport=NativeShellTransport()
    let native=try NativeAppCoordinator(directory:root,connectionPersistence:saved.persistence,transport:transport)
    let model=AppModel(native:native,legacyDraftStore:legacy,pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{}))
    await model.start();let client=try #require(native.connection.client)
    let target=OpenCodeTarget(connectionID:try #require(saved.value?.connection.id),projectID:"project",sessionID:"ses_owned",directory:"/project")
    try await native.journal.saveDraft("Keep after Keychain failure",for:target)
    saved.failRemove=true
    let report=try #require(await model.resetLocalData())
    #expect(!report.credentialsRemoved && !model.isRetired)
    #expect(native.connection.client==nil && saved.value != nil)
    #expect(native.journal.draft(for:target)=="Keep after Keychain failure")
    #expect(FileManager.default.fileExists(atPath:root.appending(path:"native-conversations.json").path))
    await #expect(throws:(any Error).self){try await client.info()}
    saved.failRemove=false
    #expect(await model.resetLocalData()?.credentialsRemoved==true)
    #expect(saved.value==nil)
  }
}
