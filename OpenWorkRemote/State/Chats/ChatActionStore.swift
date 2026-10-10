import Foundation
import Observation
import OpenWorkRemoteCore

struct ChatActionContext: Equatable, Sendable {
  let hostId: String, workspaceId: String, sessionId: String
  let generation: UUID
}
struct ChatActionIntent: Codable, Sendable {
  enum Phase: String, Codable, Sendable { case sending, uncertain }
  let hostId: String, workspaceId: String, sessionId: String
  let requestId: UUID
  let revision: String
  let action: SessionAction
  var phase: Phase
}
private struct ChatActionDisk: Codable, Sendable { var intents: [ChatActionIntent] = [] }
@MainActor @Observable final class ChatActionStore {
  private(set) var context: ChatActionContext?
  private(set) var preview: SessionActionPreview?
  private(set) var availability: FeatureAvailability = .unsupported
  private(set) var loading = false
  private(set) var needsRefresh = false
  private(set) var ready = false
  private(set) var reviewed = false
  private(set) var notice: String?
  private(set) var reviewedChats: [ChatSession] = []
  private var disk = ChatActionDisk()
  private let directory: URL
  private let persistence: RevisionedSnapshotStore<ChatActionDisk>
  private var version: UInt64 = 0
  @ObservationIgnored private var readID = UUID()
  @ObservationIgnored private var readTask: Task<SessionActionPreview, any Error>?
  var pending: ChatActionIntent? {
    guard let c = context else { return nil }
    return disk.intents.first {
      $0.hostId == c.hostId && $0.workspaceId == c.workspaceId && $0.sessionId == c.sessionId
    }
  }
  func blocksSending(_ key:DraftKey?) -> Bool {
    guard let key else{return false}
    return disk.intents.contains { $0.hostId==key.hostId && $0.workspaceId==key.workspaceId && $0.sessionId==key.sessionId && ($0.action == .delete || $0.phase == .sending) }
  }
  var saving: Bool { pending?.phase == .sending }
  var canAct: Bool {
    ready && availability == .available && preview != nil && !needsRefresh && pending == nil
  }
  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "OpenWorkRemote", directoryHint: .isDirectory)
    persistence = RevisionedSnapshotStore(url: self.directory.appending(path: "chat-actions.json"))
  }
  func restore() async throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
    disk = try await persistence.load() ?? ChatActionDisk()
    guard disk.intents.count <= 100 else { throw RemoteError.oversized }
    for n in disk.intents.indices { disk.intents[n].phase = .uncertain }
    ready = true
  }
  private func persist() async throws {
    version += 1
    try await persistence.save(disk, revision: version)
  }
  func resetLocalData() async throws {
    activate(nil)
    ready = false
    try await persistence.invalidateAndRemove()
    disk = ChatActionDisk()
  }
  func activate(_ c: ChatActionContext?) {
    guard context != c else { return }
    readID = UUID()
    readTask?.cancel()
    readTask = nil
    context = c
    preview = nil
    availability = .unsupported
    loading = false
    needsRefresh = false
    notice = nil
    reviewed = false
    reviewedChats = []
  }
  private func allowed(_ client: BridgeClient, _ c: ChatActionContext) async throws {
    let a = try await client.deviceAccess()
    guard a.allWorkspaces || a.workspaceIds.contains(c.workspaceId) else {
      throw RemoteError.forbidden
    }
  }
  func refresh(client: BridgeClient, context c: ChatActionContext, supported: Bool) async {
    guard context == c, !saving else { return }
    readTask?.cancel()
    let run = UUID()
    readID = run
    guard supported else {
      preview = nil
      availability = .unsupported
      loading = false
      readTask = nil
      return
    }
    loading = true
    let task = Task {
      try await self.allowed(client, c)
      return try await client.sessionActions(c.workspaceId, c.sessionId)
    }
    readTask = task
    defer {
      if readID == run {
        loading = false
        readTask = nil
      }
    }
    do {
      let p = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard context == c, readID == run, !Task.isCancelled else { return }
      preview = p
      availability = .available
      needsRefresh = false
      if pending == nil { notice = nil }
    } catch {
      guard context == c, readID == run, !Task.isCancelled else { return }
      needsRefresh = true
      preview = nil
      notice = "This chat could not be checked. Refresh or continue on your computer."
    }
  }
  func mutate(
    _ action: SessionAction, client: BridgeClient, context c: ChatActionContext,
    expectedRevision: String
  ) async -> String? {
    guard context == c, canAct, let p = preview else { return nil }
    guard expectedRevision == p.revision else {
      notice = "This chat changed while the confirmation was open. Refresh and review it again."
      needsRefresh = true
      return nil
    }
    guard action == .delete ? p.deleteAvailable : p.forkAvailable else { return nil }
    guard disk.intents.count < 100 else {
      notice = "Too many unreviewed actions are saved. Review them before continuing."
      return nil
    }
    let intent = ChatActionIntent(
      hostId: c.hostId, workspaceId: c.workspaceId, sessionId: c.sessionId, requestId: UUID(),
      revision: p.revision, action: action, phase: .sending)
    disk.intents.append(intent)
    notice = nil
    reviewed = false
    do { try await persist() } catch {
      disk.intents.removeAll { $0.requestId == intent.requestId }
      ready = false
      notice = "The action could not be saved safely. Continue on your computer."
      return nil
    }
    var dispatched = false
    var knownReceiptRejection = false
    do {
      try await allowed(client, c)
      guard context == c, !Task.isCancelled else { throw RemoteError.cancelled }
      dispatched = true
      let r = try await client.sessionAction(
        c.workspaceId, c.sessionId, action: action, revision: intent.revision,
        requestId: intent.requestId)
      knownReceiptRejection = r.state == "rejected"
      guard ["accepted", "confirmed"].contains(r.state), let result = r.resourceId else {
        throw RemoteError.outcomeUnknown
      }
      disk.intents.removeAll { $0.requestId == intent.requestId }
      try await persist()
      guard context == c, !Task.isCancelled else { return nil }
      return result
    } catch {
      let known =
        !dispatched || knownReceiptRejection
        || [RemoteError.conflict, .notFound, .unauthorized].contains(where: {
          $0 == (error as? RemoteError)
        })
      if known {
        disk.intents.removeAll { $0.requestId == intent.requestId }
      } else if let n = disk.intents.firstIndex(where: { $0.requestId == intent.requestId }) {
        disk.intents[n].phase = .uncertain
      } else if dispatched {
        var uncertain = intent
        uncertain.phase = .uncertain
        disk.intents.append(uncertain)
      }
      do { try await persist() } catch { ready = false }
      guard context == c, !Task.isCancelled else { return nil }
      needsRefresh = true
      notice =
        known
        ? "The action was not applied. Refresh and review this chat again."
        : "The action could not be confirmed. Check recent chats and continue on your computer if the result is unclear. It will not be sent again automatically."
      return nil
    }
  }
  func reviewChats(client: BridgeClient, context c: ChatActionContext) async {
    guard context == c, pending?.phase == .uncertain else { return }
    do {
      try await allowed(client, c)
      let page = try await client.sessions(c.workspaceId)
      guard context == c, !Task.isCancelled else { return }
      reviewedChats = page.data
      reviewed = true
    } catch {
      guard context == c else { return }
      reviewed = false
      notice =
        "Recent chats could not be checked. Reconnect or review this action on your computer."
    }
  }
  func keepCurrentChats(context c: ChatActionContext) async throws {
    guard context == c, reviewed, pending?.phase == .uncertain, let id = pending?.requestId else {
      throw RemoteError.unavailable
    }
    let previous = disk
    disk.intents.removeAll { $0.requestId == id }
    do { try await persist() } catch { disk = previous; ready = false; throw error }
    reviewed = false
    notice = nil
    needsRefresh = true
  }
}
