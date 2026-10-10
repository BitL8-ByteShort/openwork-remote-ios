import Foundation
import Observation
import OpenWorkRemoteCore

struct SkillContext: Equatable, Sendable {
  let hostId: String, workspaceId: String, generation: UUID
}
struct SkillDraft: Codable, Sendable, Equatable {
  let hostId: String, workspaceId: String, id: String?, revision: String?, catalogRevision: String
  var name: String, content: String
}
struct SkillIntent: Codable, Sendable {
  enum Phase: String, Codable, Sendable { case sending, uncertain }
  let hostId: String, workspaceId: String, requestId: UUID, action: SkillAction
  var phase: Phase
}
private struct SkillDisk: Codable, Sendable {
  var drafts: [SkillDraft] = [], intents: [SkillIntent] = []
}
@MainActor @Observable final class SkillStore {
  private(set) var context: SkillContext?
  private(set) var catalog: SkillCatalog?
  private(set) var availability: FeatureAvailability = .unsupported
  private(set) var loading = false
  private(set) var needsRefresh = false
  private(set) var ready = false
  private(set) var administration = false
  private(set) var writeSupported = false
  private(set) var reviewed = false
  private(set) var notice: String?
  private var disk = SkillDisk()
  private var version: UInt64 = 0
  private var draftGeneration = UUID()
  private let directory: URL, persistence: RevisionedSnapshotStore<SkillDisk>
  @ObservationIgnored private var readID = UUID()
  @ObservationIgnored private var readTask: Task<SkillCatalog, any Error>?
  @ObservationIgnored private var draftTask: Task<Void, Never>?
  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "OpenWorkRemote", directoryHint: .isDirectory)
    persistence = RevisionedSnapshotStore(url: self.directory.appending(path: "skills.json"))
  }
  var pending: SkillIntent? {
    guard let c = context else { return nil }
    return disk.intents.first { $0.hostId == c.hostId && $0.workspaceId == c.workspaceId }
  }
  var saving: Bool { pending?.phase == .sending }
  var canEdit: Bool {
    ready && availability == .available && administration && writeSupported && !loading
      && !needsRefresh && pending == nil && catalog != nil
  }
  var canReview: Bool { pending?.phase == .uncertain && reviewed && !needsRefresh }
  func restore() async throws {
    var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
    #if os(iOS)
      attributes[.protectionKey] = FileProtectionType.complete
    #endif
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: attributes)
    let file = directory.appending(path: "skills.json")
    if FileManager.default.fileExists(atPath: file.path),
      let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
      size.intValue > 12 * 1024 * 1024
    {
      throw RemoteError.oversized
    }
    disk = try await persistence.load() ?? SkillDisk()
    guard disk.drafts.count <= 50, disk.intents.count <= 100 else { throw RemoteError.oversized }
    for d in disk.drafts {
      guard d.name.count <= 64 else { throw RemoteError.oversized }
      try SkillValidation.revision(d.catalogRevision)
      if let id = d.id { try SkillValidation.id(id) }
      if let revision = d.revision { try SkillValidation.revision(revision) }
      guard d.content.utf8.count <= 65536 else { throw RemoteError.oversized }
    }
    for n in disk.intents.indices {
      try disk.intents[n].action.validate()
      disk.intents[n].phase = .uncertain
    }
    ready = true
  }
  func flush() async throws {
    draftTask?.cancel()
    draftTask = nil
    guard try JSONEncoder().encode(disk).count <= 12 * 1024 * 1024 else {
      ready = false
      throw RemoteError.oversized
    }
    version += 1
    try await persistence.save(disk, revision: version)
  }
  func clearUnsentDrafts() async throws {
    draftGeneration = UUID()
    draftTask?.cancel()
    draftTask = nil
    disk.drafts.removeAll()
    try await flush()
  }
  func resetLocalData() async throws {
    draftTask?.cancel()
    draftTask = nil
    activate(nil)
    ready = false
    try await persistence.invalidateAndRemove()
    disk = SkillDisk()
  }
  func activate(_ c: SkillContext?) {
    guard context != c else { return }
    readID = UUID()
    readTask?.cancel()
    readTask = nil
    context = c
    catalog = nil
    availability = .unsupported
    loading = false
    needsRefresh = false
    administration = false
    writeSupported = false
    notice = nil
    reviewed = false
  }
  private func access(_ client: BridgeClient, _ c: SkillContext, write: Bool) async throws -> Bool {
    let a = try await client.deviceAccess()
    guard a.allWorkspaces || a.workspaceIds.contains(c.workspaceId) else {
      throw RemoteError.forbidden
    }
    if write && !a.features.workspaceAdministration { throw RemoteError.forbidden }
    return a.features.workspaceAdministration
  }
  func refresh(client: BridgeClient, context c: SkillContext, read: Bool, write: Bool) async {
    guard context == c, !saving else { return }
    readTask?.cancel()
    let run = UUID()
    readID = run
    writeSupported = write
    guard read else {
      catalog = nil
      availability = .unsupported
      loading = false
      return
    }
    loading = true
    let task = Task { try await client.skills(c.workspaceId) }
    readTask = task
    defer {
      if readID == run {
        loading = false
        readTask = nil
      }
    }
    do {
      let granted = try await access(client, c, write: false)
      let value = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard context == c, readID == run, !Task.isCancelled else { return }
      catalog = value
      administration = granted
      availability = .available
      needsRefresh = false
      reviewed = pending?.phase == .uncertain
      notice = nil
    } catch {
      guard context == c, readID == run, !Task.isCancelled else { return }
      needsRefresh = true
      if (error as? RemoteError) == .forbidden {
        catalog = nil
        availability = .needsHostGrant(.workspaceAdministration)
        notice =
          "This workspace is no longer allowed for this phone. Review Remote access on your computer."
      } else if (error as? RemoteError) == .incompatible {
        catalog = nil
        availability = .unsupported
        notice =
          "Skills are unavailable on this computer. Update OpenWork Remote Preview or manage them on your computer."
      } else {
        notice = "Skills could not be checked. Your drafts are kept; reconnect and refresh."
      }
    }
  }
  func detail(_ id: String, client: BridgeClient, context c: SkillContext) async throws
    -> SkillDetail
  {
    guard context == c else { throw RemoteError.cancelled }
    _ = try await access(client, c, write: false)
    let result = try await client.skill(c.workspaceId, id: id)
    guard context == c, !Task.isCancelled else { throw RemoteError.cancelled }
    return result
  }
  func draft(id: String?, context c: SkillContext) -> SkillDraft? {
    disk.drafts.first { $0.hostId == c.hostId && $0.workspaceId == c.workspaceId && $0.id == id }
  }
  func beginDraft(detail: SkillDetail?, context c: SkillContext) throws -> SkillDraft {
    guard context == c, let catalog, ready else { throw RemoteError.unavailable }
    if let saved = draft(id: detail?.item.id, context: c) { return saved }
    guard detail == nil || detail?.item.editable == true else { throw RemoteError.skillProtected }
    guard disk.drafts.count < 50 else { throw RemoteError.oversized }
    let name = detail?.item.name ?? "my-skill"
    let content =
      detail?.content
      ?? "---\nname: my-skill\ndescription: Describe when to use this skill.\n---\n\nWrite the instructions here.\n"
    let value = SkillDraft(
      hostId: c.hostId, workspaceId: c.workspaceId, id: detail?.item.id,
      revision: detail?.item.revision, catalogRevision: catalog.revision, name: name,
      content: content)
    disk.drafts.append(value)
    scheduleDraftSave()
    return value
  }
  func updateDraft(_ d: SkillDraft, context c: SkillContext) throws {
    guard context == c, d.hostId == c.hostId, d.workspaceId == c.workspaceId, !saving,
      let i = disk.drafts.firstIndex(where: {
        $0.hostId == d.hostId && $0.workspaceId == d.workspaceId && $0.id == d.id
      })
    else { throw RemoteError.unavailable }
    guard d.content.utf8.count <= 65536, d.name.count <= 64 else { throw RemoteError.oversized }
    disk.drafts[i] = d
    scheduleDraftSave()
  }
  private func scheduleDraftSave() {
    draftTask?.cancel()
    draftTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(250))
        draftTask = nil
        try await flush()
      } catch {
        if !Task.isCancelled {
          ready = false
          notice =
            "Your skill draft could not be saved safely. Keep this screen open and copy the instructions before leaving."
        }
      }
    }
  }
  func replaceDraft(detail: SkillDetail, context c: SkillContext) async throws -> SkillDraft {
    guard context == c, !saving, ready, let catalog, detail.item.editable,
      let content = detail.content
    else { throw RemoteError.unavailable }
    let old = draft(id: detail.item.id, context: c)
    let updated = SkillDraft(
      hostId: c.hostId, workspaceId: c.workspaceId, id: detail.item.id,
      revision: detail.item.revision, catalogRevision: catalog.revision, name: detail.item.name,
      content: content)
    disk.drafts.removeAll {
      $0.hostId == c.hostId && $0.workspaceId == c.workspaceId && $0.id == detail.item.id
    }
    disk.drafts.append(updated)
    do {
      try await flush()
      return updated
    } catch {
      if let index = disk.drafts.firstIndex(of: updated) {
        disk.drafts.remove(at: index)
        if let old { disk.drafts.append(old) }
      }
      ready = false
      throw error
    }
  }
  func discardDraft(id: String?, context c: SkillContext) async throws {
    guard context == c, !saving else { throw RemoteError.unavailable }
    disk.drafts.removeAll {
      $0.hostId == c.hostId && $0.workspaceId == c.workspaceId && $0.id == id
    }
    try await flush()
  }
  func change(_ action: SkillAction, client: BridgeClient, context c: SkillContext) async -> Bool {
    guard context == c, canEdit, let catalog, disk.intents.count < 100 else { return false }
    do { try action.validate() } catch {
      notice = "Check the skill name, text and size. Your draft is kept."
      return false
    }
    switch action {
    case .save(let name, _, let revision, let base):
      if let revision {
        guard
          catalog.items.contains(where: {
            $0.name == name && $0.editable && $0.revision == revision
          })
        else {
          notice =
            "This skill changed on your computer. Refresh and review the current instructions; your draft is kept."
          return false
        }
      } else {
        guard base == catalog.revision else {
          notice = "The skills changed. Refresh before adding your draft."
          return false
        }
      }
    case .delete(let id, let revision):
      guard catalog.items.contains(where: { $0.id == id && $0.editable && $0.revision == revision })
      else {
        notice = "This skill changed. Refresh before removing it."
        return false
      }
    }
    let savedDrafts = disk.drafts.filter {
      $0.hostId == c.hostId && $0.workspaceId == c.workspaceId
    }
    let savedDraftGeneration = draftGeneration
    let rid = UUID()
    do { _ = try action.requestBody(requestId: rid) } catch {
      notice =
        "This request exceeds the supported size or format. Your draft is kept; continue on your computer."
      return false
    }
    let intent = SkillIntent(
      hostId: c.hostId, workspaceId: c.workspaceId, requestId: rid, action: action, phase: .sending)
    disk.intents.append(intent)
    notice = nil
    reviewed = false
    do { try await flush() } catch {
      disk.intents.removeAll { $0.requestId == intent.requestId }
      ready = false
      notice = "The request could not be saved safely. Nothing was sent."
      return false
    }
    var dispatched = false
    do {
      _ = try await access(client, c, write: true)
      guard context == c, !Task.isCancelled else { throw RemoteError.cancelled }
      dispatched = true
      let receipt = try await client.changeSkill(
        c.workspaceId, action: action, requestId: intent.requestId)
      guard ["accepted", "confirmed"].contains(receipt.state), let resource = receipt.resourceId
      else { throw RemoteError.outcomeUnknown }
      let actual = try await client.skills(c.workspaceId)
      _ = try await access(client, c, write: true)
      guard context == c, !Task.isCancelled else { throw RemoteError.outcomeUnknown }
      switch action {
      case .save(let name, _, _, _):
        guard
          actual.items.contains(where: {
            $0.id == resource && $0.name == name && $0.editable
              && $0.revision == receipt.resourceRevision
          })
        else { throw RemoteError.outcomeUnknown }
      case .delete(let id, _):
        guard !actual.items.contains(where: { $0.id == id }) else {
          throw RemoteError.outcomeUnknown
        }
      }
      self.catalog = actual
      disk.intents.removeAll { $0.requestId == intent.requestId }
      switch action {
      case .save(let name, _, _, _):
        disk.drafts.removeAll {
          $0.hostId == c.hostId && $0.workspaceId == c.workspaceId && $0.name == name
        }
      case .delete(let id, _):
        disk.drafts.removeAll {
          $0.hostId == c.hostId && $0.workspaceId == c.workspaceId && $0.id == id
        }
      }
      try await flush()
      needsRefresh = false
      return true
    } catch {
      let e = error as? RemoteError
      let known =
        !dispatched || e == .conflict || e == .skillWriteDenied || e == .skillProtected
        || e == .skillInvalid || e == .unauthorized
      if known {
        disk.intents.removeAll { $0.requestId == intent.requestId }
      } else {
        if let n = disk.intents.firstIndex(where: { $0.requestId == intent.requestId }) {
          disk.intents[n].phase = .uncertain
        } else {
          var uncertain = intent
          uncertain.phase = .uncertain
          disk.intents.append(uncertain)
        }
        for d in savedDrafts
        where draftGeneration == savedDraftGeneration && !disk.drafts.contains(where: {
          $0.hostId == d.hostId && $0.workspaceId == d.workspaceId && $0.id == d.id
        }) { disk.drafts.append(d) }
      }
      do { try await flush() } catch { ready = false }
      guard context == c, !Task.isCancelled else { return false }
      needsRefresh = true
      notice =
        e == .skillWriteDenied
        ? "OpenWork did not approve this change. Your draft is kept; review it on your computer."
        : known
          ? "This change was not saved. Your draft is kept; refresh and review the current skill."
          : "The change is unconfirmed and may be waiting for approval on your computer. Refresh and review before making another change."
      return false
    }
  }
  func acknowledgeCurrent(context c: SkillContext) async throws {
    guard context == c, canReview, let pending else { throw RemoteError.unavailable }
    disk.intents.removeAll { $0.requestId == pending.requestId }
    try await flush()
    reviewed = false
    notice = nil
  }
}
