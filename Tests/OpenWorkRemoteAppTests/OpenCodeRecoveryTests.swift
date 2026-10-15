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
}
@Suite @MainActor struct OpenCodeRecoveryTests {
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
