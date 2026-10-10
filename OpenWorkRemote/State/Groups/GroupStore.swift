import Foundation
import Observation
import OpenWorkRemoteCore

struct GroupContext: Equatable, Sendable {
  let hostId: String
  let workspaceId: String
  let generation: UUID
}
struct GroupIntent: Codable, Sendable {
  enum Phase: String, Codable, Sendable { case sending, uncertain }
  let hostId: String
  let workspaceId: String
  let requestId: UUID
  let revision: String
  let action: GroupAction
  var phase: Phase
}
private struct GroupDisk: Codable, Sendable { var intents: [GroupIntent] = [] }
@MainActor @Observable final class GroupStore {
  private(set) var context: GroupContext?
  private(set) var snapshot: GroupSnapshot?
  private(set) var availability: FeatureAvailability = .unsupported
  private(set) var loading = false
  private(set) var needsRefresh = false
  private(set) var notice: String?
  private(set) var verifiedAt: Date?
  private(set) var ready = false
  private var disk = GroupDisk()
  private let directory: URL
  private let persistence: RevisionedSnapshotStore<GroupDisk>
  private var version: UInt64 = 0
  @ObservationIgnored private var readID = UUID()
  @ObservationIgnored private var readTask: Task<GroupSnapshot, any Error>?
  private var reviewedUncertain = false
  var pending: GroupIntent? {
    guard let c = context else { return nil }
    return disk.intents.first { $0.hostId == c.hostId && $0.workspaceId == c.workspaceId }
  }
  var saving: Bool { pending?.phase == .sending }
  var canEdit: Bool {
    ready && availability == .available && snapshot != nil && !needsRefresh && pending == nil
  }
  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "OpenWorkRemote", directoryHint: .isDirectory)
    persistence = RevisionedSnapshotStore(url: self.directory.appending(path: "groups.json"))
  }
  func restore() async throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
    disk = try await persistence.load() ?? GroupDisk()
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
    disk = GroupDisk()
  }
  func activate(_ value: GroupContext?) {
    guard context != value else { return }
    readID = UUID()
    readTask?.cancel()
    readTask = nil
    context = value
    snapshot = nil
    availability = .unsupported
    loading = false
    needsRefresh = false
    notice = nil
    verifiedAt = nil
    reviewedUncertain = false
  }
  private func allowed(_ client: BridgeClient, _ c: GroupContext) async throws {
    let access = try await client.deviceAccess()
    guard access.allWorkspaces || access.workspaceIds.contains(c.workspaceId) else {
      throw RemoteError.forbidden
    }
  }
  func refresh(client: BridgeClient, context c: GroupContext, supported: Bool) async {
    guard context == c, !saving else { return }
    readTask?.cancel()
    let run = UUID()
    readID = run
    guard supported else {
      availability = .unsupported
      snapshot = nil
      notice = nil
      needsRefresh = false
      loading = false
      readTask = nil
      return
    }
    loading = true
    let task = Task {
      try await self.allowed(client, c)
      return try await client.sessionGroups(c.workspaceId)
    }
    readTask = task
    defer {
      if readID == run {
        loading = false
        readTask = nil
      }
    }
    do {
      let result = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard context == c, readID == run, !Task.isCancelled else { return }
      snapshot = result
      availability = .available
      verifiedAt = Date()
      needsRefresh = false
      notice = nil
      reviewedUncertain = pending?.phase == .uncertain
    } catch {
      guard context == c, readID == run, !Task.isCancelled else { return }
      needsRefresh = true
      if case RemoteError.forbidden = error {
        snapshot = nil
        availability = .unsupported
        notice =
          "This project is no longer allowed. Change project access in Remote access on your computer."
      } else {
        notice = "Groups could not be checked. Refresh or continue on your computer."
      }
    }
  }
  private func remove(_ id: UUID) { disk.intents.removeAll { $0.requestId == id } }
  func mutate(
    _ action: GroupAction, client: BridgeClient, context c: GroupContext,
    expectedRevision: String? = nil
  ) async -> Bool {
    guard context == c, canEdit, let snapshot else { return false }
    guard expectedRevision == nil || expectedRevision == snapshot.revision else {
      notice = "Groups changed while this form was open. Refresh and review before saving."
      return false
    }
    let intent = GroupIntent(
      hostId: c.hostId, workspaceId: c.workspaceId, requestId: UUID(), revision: snapshot.revision,
      action: action, phase: .sending)
    disk.intents.append(intent)
    notice = nil
    reviewedUncertain = false
    do { try await persist() } catch {
      remove(intent.requestId)
      ready = false
      notice = "The change could not be saved safely. Continue on your computer."
      return false
    }
    guard context == c, !Task.isCancelled else {
      remove(intent.requestId)
      try? await persist()
      return false
    }
    var dispatched = false
    do {
      try await allowed(client, c)
      guard context == c, !Task.isCancelled else { throw RemoteError.cancelled }
      dispatched = true
      let result = try await client.changeGroup(
        c.workspaceId, action: action, revision: intent.revision, requestId: intent.requestId)
      guard ["accepted", "confirmed"].contains(result.state) else {
        throw RemoteError.outcomeUnknown
      }
      remove(intent.requestId)
      try await persist()
      guard context == c, !Task.isCancelled else { return false }
      await refresh(client: client, context: c, supported: true)
      return true
    } catch {
      let knownRejection =
        !dispatched
        || [RemoteError.conflict, .notFound, .forbidden, .unauthorized, .incompatible].contains(
          where: { $0 == (error as? RemoteError) })
      if knownRejection {
        remove(intent.requestId)
      } else if let n = disk.intents.firstIndex(where: { $0.requestId == intent.requestId }) {
        disk.intents[n].phase = .uncertain
      }
      do { try await persist() } catch { ready = false }
      guard context == c, !Task.isCancelled else { return false }
      needsRefresh = true
      if case RemoteError.conflict = error {
        notice = "Groups changed on your computer. Refresh before saving again."
      } else if knownRejection {
        notice =
          "The group change was not applied. Refresh or check project access on your computer."
      } else {
        notice =
          "The group change could not be confirmed. Review current groups before making another change."
      }
      return false
    }
  }
  // Explicitly accepts the latest host state, without claiming an uncertain
  // phone action succeeded and without replaying or generating a retry UUID.
  func keepCurrentGroups(context c: GroupContext) async throws {
    guard context == c, pending?.phase == .uncertain, reviewedUncertain, !needsRefresh,
      let id = pending?.requestId
    else { throw RemoteError.unavailable }
    remove(id)
    try await persist()
    notice = nil
    reviewedUncertain = false
  }
  var canKeepCurrentGroups: Bool {
    pending?.phase == .uncertain && reviewedUncertain && !needsRefresh
  }
}
