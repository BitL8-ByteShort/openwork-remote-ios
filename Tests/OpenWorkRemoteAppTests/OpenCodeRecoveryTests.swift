import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor MemoryNativeConversationFile:NativeConversationPersistence {
  var value=NativeConversationDisk()
  var fail=false
  func load() async throws -> NativeConversationDisk{value}
  func save(_ value:NativeConversationDisk,revision:UInt64) async throws {
    if fail{throw RemoteError.unavailable};self.value=value
  }
  func failWrites(){fail=true}
  func seed(_ disk:NativeConversationDisk){value=disk}
}
@Suite @MainActor struct OpenCodeRecoveryTests {
  @Test func unscopedPreviewDraftsRequireExplicitTextRecoveryWhilePendingKeepsItsTarget()async throws{
    struct PreviewDisk:Encodable{
      let schemaVersion=1
      let drafts:[DraftKey:String]
      let pending:[DraftKey:NativePendingPrompt]
    }
    let persistence=MemoryNativeConversationFile(),old=target()
    let key=DraftKey(hostId:"opencode-v2:"+old.connectionID.rawValue.uuidString.lowercased(),workspaceId:old.projectID,sessionId:old.sessionID)
    let item=NativePendingPrompt(target:old,prompt:try OpenCodePrompt(text:"Possibly admitted"),state:.prepared)
    let data=try JSONEncoder().encode(PreviewDisk(drafts:[key:"Unscoped preview text"],pending:[key:item]))
    let upgraded=try JSONDecoder().decode(NativeConversationDisk.self,from:data);try upgraded.validate()
    await persistence.seed(upgraded)
    let journal=NativeConversationJournal(persistence:persistence);try await journal.restore()
    #expect(journal.draft(for:old).isEmpty)
    #expect(journal.pending(for:old)?.state == .unknown)
    let recovery=try #require(journal.recoverableDrafts.first)
    let replacement=target()
    try await journal.copyRecoveredDraft(recovery,to:replacement,expectedDraft:"")
    #expect(journal.draft(for:replacement)=="Unscoped preview text")
    #expect(journal.attachments(for:replacement).isEmpty && journal.skills(for:replacement).isEmpty)
    #expect(journal.pending(for:replacement)==nil && journal.pending(for:old) != nil)
    #expect(journal.recoverableDrafts.contains{$0.id == .earlier(key)})
    let relaunched=NativeConversationJournal(persistence:persistence);try await relaunched.restore()
    #expect(relaunched.draft(for:replacement)=="Unscoped preview text")
    #expect(relaunched.recoverableDrafts.count==2)
  }
  @Test func recoveryCannotOverwriteANewerDraftOrAnUncertainSend()async throws{
    let journal=NativeConversationJournal(persistence:MemoryNativeConversationFile()),source=target(),destination=target()
    try await journal.restore();try await journal.saveDraft("Recovery",for:source)
    let recovery=try #require(journal.recoverableDrafts.first)
    try await journal.saveDraft("Edited meanwhile",for:destination)
    await #expect(throws:RemoteError.conflict){try await journal.copyRecoveredDraft(recovery,to:destination,expectedDraft:"")}
    _ = try await journal.prepare(target:destination)
    await #expect(throws:RemoteError.conflict){try await journal.copyRecoveredDraft(recovery,to:destination,expectedDraft:"Edited meanwhile")}
    #expect(journal.draft(for:destination)=="Edited meanwhile")
  }
  @Test func movingAChatDoesNotReassociateDraftsOrPendingWork()async throws{
    let persistence=MemoryNativeConversationFile(),journal=NativeConversationJournal(persistence:persistence),old=target()
    let moved=OpenCodeTarget(connectionID:old.connectionID,projectID:old.projectID,sessionID:old.sessionID,directory:"/moved")
    try await journal.restore();try await journal.saveDraft("Original folder text",for:old)
    let pending=try await journal.prepare(target:old)
    #expect(journal.draft(for:moved).isEmpty)
    #expect(journal.pending(for:moved)==nil)
    try await journal.saveDraft("Moved folder text",for:moved)
    #expect(journal.draft(for:old)=="Original folder text")
    let restored=NativeConversationJournal(persistence:persistence);try await restored.restore()
    #expect(restored.pending(for:old)?.prompt.id==pending.prompt.id)
    #expect(restored.pending(for:moved)==nil)
    #expect(restored.draft(for:moved)=="Moved folder text")
  }
  @Test func rawUnicodeFolderAndProjectNamesKeepSeparateDrafts()async throws{
    let journal=NativeConversationJournal(persistence:MemoryNativeConversationFile()),id=ConnectionID()
    let a=OpenCodeTarget(connectionID:id,projectID:"pr\u{e9}",sessionID:"ses_owned",directory:"/caf\u{e9}")
    let b=OpenCodeTarget(connectionID:id,projectID:"pre\u{301}",sessionID:"ses_owned",directory:"/cafe\u{301}")
    try await journal.restore();try await journal.saveDraft("Composed",for:a);try await journal.saveDraft("Decomposed",for:b)
    #expect(journal.draft(for:a)=="Composed" && journal.draft(for:b)=="Decomposed")
  }
  func target(_ connection:ConnectionID=ConnectionID())->OpenCodeTarget {
    OpenCodeTarget(connectionID:connection,projectID:"project",sessionID:"ses_owned",directory:"/project")
  }
  @Test func durableIntentSurvivesRelaunchWithoutAutomaticResend() async throws {
    let persistence=MemoryNativeConversationFile(),journal=NativeConversationJournal(persistence:persistence),target=target()
    try await journal.restore();try await journal.saveDraft("Original",for:target)
    let pending=try await journal.prepare(target:target)
    try await journal.saveDraft("Unrelated new text",for:target)
    let restored=NativeConversationJournal(persistence:persistence)
    try await restored.restore()
    #expect(restored.pending(for:target)?.prompt.id==pending.prompt.id)
    #expect(restored.pending(for:target)?.prompt.text=="Original")
    #expect(restored.draft(for:target)=="Unrelated new text")
    #expect(restored.pending(for:target)?.state == .unknown)
  }
  @Test func acknowledgementCannotClearTextEditedWhileSending() async throws {
    let journal=NativeConversationJournal(persistence:MemoryNativeConversationFile()),target=target()
    try await journal.restore();try await journal.saveDraft("Original",for:target)
    let pending=try await journal.prepare(target:target)
    try await journal.saveDraft("New text",for:target)
    try await journal.confirm(pending)
    #expect(journal.draft(for:target)=="New text")
    #expect(journal.pending(for:target)==nil)
  }
  @Test func storageFailureNeverReturnsASendableIntent() async throws {
    let persistence=MemoryNativeConversationFile(),journal=NativeConversationJournal(persistence:persistence),target=target()
    try await journal.restore();try await journal.saveDraft("Original",for:target)
    await persistence.failWrites()
    await #expect(throws:RemoteError.unavailable){_ = try await journal.prepare(target:target)}
    #expect(journal.draft(for:target)=="Original")
    #expect(journal.storageIssue)
  }
  @Test func equalChatIDsOnAnotherConnectionCannotClearPendingWork() async throws {
    let journal=NativeConversationJournal(persistence:MemoryNativeConversationFile()),a=target(),b=target()
    try await journal.restore();try await journal.saveDraft("A",for:a);try await journal.saveDraft("B",for:b)
    let first=try await journal.prepare(target:a),second=try await journal.prepare(target:b)
    try await journal.confirm(second)
    #expect(journal.pending(for:a)?.prompt.id==first.prompt.id)
    #expect(journal.draft(for:a)=="A");#expect(journal.draft(for:b).isEmpty)
  }
}
