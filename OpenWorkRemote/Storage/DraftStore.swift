import Foundation
import OpenWorkRemoteCore

struct DiskState: Codable, Sendable {
  var conversation = ConversationState()
  var cursors: [String: String] = [:]
  var mutations = MutationState()
}
actor DraftStore {
  nonisolated let directory: URL
  private let snapshots: RevisionedSnapshotStore<DiskState>
  init(directory: URL? = nil) throws {
    let root = try directory ?? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appending(path: "OpenWorkRemote", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
    self.directory = root
    snapshots = RevisionedSnapshotStore(url: root.appending(path: "drafts.json"))
  }
  func load() async throws -> DiskState {
    var state = try await snapshots.load() ?? DiskState()
    state.conversation.recoverPending()
    state.mutations.recoverPending()
    return state
  }
  func save(_ state: DiskState, revision: UInt64) async throws {
    let span = InteractionMetrics.begin("Persist draft snapshot")
    defer { InteractionMetrics.end("Persist draft snapshot", span) }
    try await snapshots.save(state, revision: revision)
  }
}
