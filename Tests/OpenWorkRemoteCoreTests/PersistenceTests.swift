import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Test func delayedDraftSaveCannotOverwriteDurableSendIntent() async throws {
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = RevisionedSnapshotStore<ConversationState>(url: directory.appending(path: "state.json"))
  var state = ConversationState()
  state.select(DraftKey(hostId: "host", workspaceId: "workspace", sessionId: "chat"))
  state.setDraft("Keep my message")
  let oldDraft = state
  let intent = try state.beginSend(ready: true)
  try await store.save(state, revision: 2)
  try await store.save(oldDraft, revision: 1)
  let restored = try await store.load()
  #expect(restored?.pendingRequestId(for: intent.key) == intent.requestId)
  #expect(restored?.currentDraft == "Keep my message")
}
