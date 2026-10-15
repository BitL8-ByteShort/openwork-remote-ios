import Foundation
import OpenWorkRemoteCore

private struct LegacyDiscardedMetadata: Codable, Sendable {}
/// Decode the earlier schema with its existing restore limits. A corrupt or
/// unsupported recovery record must not be rewritten by a draft-clear action.
private struct LegacySkillRecoveryDisk: Codable, Sendable {
  var value: SkillDisk
  init(value: SkillDisk) { self.value = value }
  init(from decoder: any Decoder) throws {
    value = try SkillDisk(from: decoder)
    guard value.drafts.count <= 50, value.intents.count <= 100 else { throw RemoteError.oversized }
    for draft in value.drafts {
      guard draft.name.count <= 64, draft.content.utf8.count <= 65_536 else { throw RemoteError.oversized }
      try SkillValidation.revision(draft.catalogRevision)
      if let id = draft.id { try SkillValidation.id(id) }
      if let revision = draft.revision { try SkillValidation.revision(revision) }
    }
    for intent in value.intents { try intent.action.validate() }
  }
  func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}
private protocol LegacyResettable: Sendable {
  func retire() async
  func invalidateAndRemove() async throws
}
extension RevisionedSnapshotStore: LegacyResettable {}
extension ProtectedAttachmentFiles: LegacyResettable {}
extension ProtectedArtifactFiles: LegacyResettable {}

/// The shipping app retains only local recovery/erasure of earlier beta data.
/// There is no bridge client, grant/capability state or network operation here.
actor LegacyLocalRecovery {
  private let questions: RevisionedSnapshotStore<QuestionDiskState>
  private let skills: RevisionedSnapshotStore<LegacySkillRecoveryDisk>
  private let skillFile: URL
  private let remaining: [(String, any LegacyResettable)]
  private let downloads: ProtectedArtifactFiles
  init(directory: URL) {
    questions = RevisionedSnapshotStore(url: directory.appending(path: "questions.json"))
    skillFile = directory.appending(path: "skills.json")
    skills = RevisionedSnapshotStore(url: skillFile)
    downloads = ProtectedArtifactFiles(directory: directory.appending(path: "ArtifactDownloads"))
    let metadata = [("Earlier chat action records", "chat-actions.json"),
                    ("Earlier group action records", "groups.json"),
                    ("Earlier default-model action records", "workspace-defaults.json"),
                    ("Earlier selected attachment records", "attachments.json")]
    remaining = metadata.map { label, filename in
      (label, RevisionedSnapshotStore<LegacyDiscardedMetadata>(url: directory.appending(path: filename)) as any LegacyResettable)
    } + [("Earlier selected attachment files", ProtectedAttachmentFiles(directory: directory.appending(path: "AttachmentBytes")))]
  }
  func clearUnsentDrafts() async -> Bool {
    var success = true
    do {
      try await questions.update { previous in
        var next = previous ?? QuestionDiskState()
        for index in next.drafts.indices where next.drafts[index].state == .sending {
          next.drafts[index].state = .uncertain
        }
        next.drafts.removeAll { ![.sending, .uncertain].contains($0.state) }
        return next
      }
    } catch { success = false }
    do {
      if FileManager.default.fileExists(atPath: skillFile.path),
         let size = try FileManager.default.attributesOfItem(atPath: skillFile.path)[.size] as? NSNumber,
         size.intValue > 12 * 1_024 * 1_024 { throw RemoteError.oversized }
      try await skills.update { previous in
        var next = previous?.value ?? SkillDisk()
        next.drafts.removeAll()
        for index in next.intents.indices { next.intents[index].phase = .uncertain }
        return LegacySkillRecoveryDisk(value: next)
      }
    } catch { success = false }
    return success
  }
  func clearDownloadedCopies() async throws { try await downloads.invalidateAndRemove() }
  private var components: [(String, any LegacyResettable)] {
    [("Earlier question drafts", questions), ("Earlier skill drafts", skills)]
      + remaining + [("Earlier downloaded file copies", downloads)]
  }
  func retireWriters() async { for (_, file) in components { await file.retire() } }
  func removeAll() async -> [String] {
    await retireWriters()
    var failures: [String] = []
    for (label, file) in components {
      do { try await file.invalidateAndRemove() } catch { failures.append(label) }
    }
    return failures
  }
}
