import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct DataResetPersistenceTests {
  @Test func retiredWriterCannotRecreateDeletedSnapshot() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "drafts.json")
    let old = RevisionedSnapshotStore<ConversationState>(url: url)
    try await old.save(ConversationState(), revision: 1)
    try await old.invalidateAndRemove()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    await #expect(throws: SnapshotStoreError.self) { try await old.save(ConversationState(), revision: 100) }
    let fresh = RevisionedSnapshotStore<ConversationState>(url: url)
    try await fresh.save(ConversationState(), revision: 1)
    await #expect(throws: SnapshotStoreError.self) { try await old.save(ConversationState(), revision: 101) }
    #expect(try await fresh.load() != nil)
  }
  @Test func clearingDraftsRetainsUnconfirmedSendIDAndSelection() throws {
    let key = DraftKey(hostId: "host", workspaceId: "workspace", sessionId: "chat")
    var state = ConversationState()
    state.select(key)
    state.setDraft("Private draft")
    let intent = try state.beginSend(ready: true)
    state.applyReceipt(intent, accepted: false)
    state.clearDraftText()
    #expect(state.currentDraft.isEmpty)
    #expect(state.selected == key)
    #expect(state.pendingRequestId(for: key) == intent.requestId)
    #expect(state.uncertain.contains(key))
    #expect(throws: RemoteError.self) { try state.beginSend(ready: true) }
  }
  @Test func newerClearPreventsOlderAutosaveFromRestoringText() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = RevisionedSnapshotStore<ConversationState>(url: root.appending(path: "drafts.json"))
    var draft = ConversationState()
    draft.select(DraftKey(hostId: "host", workspaceId: "workspace", sessionId: "chat"))
    draft.setDraft("Private draft")
    var cleared = draft
    cleared.clearDraftText()
    try await store.save(cleared, revision: 5)
    try await store.save(draft, revision: 4)
    #expect(try await store.load()?.currentDraft == "")
  }
  @Test func removalFailureStillRetiresTheWriter() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let url = root.appending(path: "nonempty-directory")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    // A regular file is the only permitted snapshot-removal target.
    try Data([1]).write(to: url.appending(path: "do-not-delete"))
    let store = RevisionedSnapshotStore<ConversationState>(url: url)
    await #expect(throws: SnapshotStoreError.self) { try await store.invalidateAndRemove() }
    #expect(FileManager.default.fileExists(atPath: url.appending(path: "do-not-delete").path))
    await #expect(throws: SnapshotStoreError.self) { try await store.save(ConversationState(), revision: 1) }
  }
}
