import Foundation
import Observation
import OpenWorkRemoteCore

struct AttachmentContext: Equatable, Sendable {
  let key: DraftKey
  let generation: UUID
  let selection: UUID
}
struct AttachmentDraft: Codable, Sendable, Identifiable {
  enum Phase: String, Codable, Sendable {
    case selected, allocating, uploading, committing, ready, failed, uncertain, sending, attached, cancelPending, cancelled, expired
  }
  var id: UUID { file.id }
  let key: DraftKey
  let file: LocalAttachmentFile
  var allocationID = UUID()
  var commitID = UUID()
  var cancelID = UUID()
  var attachmentID: String?
  var receivedBytes = 0
  var phase: Phase = .selected
  var promptID: UUID?
  var promptReviewed: Bool?
}
private struct AttachmentDiskState: Codable, Sendable { var drafts: [AttachmentDraft] = [] }

@MainActor @Observable final class AttachmentStore {
  let files: ProtectedAttachmentFiles
  private(set) var context: AttachmentContext?
  private(set) var availability: FeatureAvailability = .unsupported
  private(set) var limits: AttachmentLimits?
  private(set) var notice: String?
  private(set) var ready = false
  private(set) var checkingAccess = false
  private var disk = AttachmentDiskState()
  private let directory: URL
  private let snapshots: RevisionedSnapshotStore<AttachmentDiskState>
  private var revision: UInt64 = 0
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var runs: [UUID: UUID] = [:]
  private var accessRead = UUID()

  init(directory: URL? = nil) {
    let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "OpenWorkRemote", directoryHint: .isDirectory)
    self.directory = root
    files = ProtectedAttachmentFiles(directory:root.appending(path:"AttachmentBytes"))
    snapshots = RevisionedSnapshotStore(url:root.appending(path:"attachments.json"))
  }
  var rows: [AttachmentDraft] {
    guard let context else { return [] }
    return disk.drafts.filter { $0.key == context.key && ![.attached,.cancelPending,.cancelled].contains($0.phase) }
  }
  var canChoose: Bool { ready && availability == .available && limits?.inputMIMEs.isEmpty == false }
  var canSend: Bool {
    canChoose && !rows.isEmpty && rows.allSatisfy { $0.phase == .ready && $0.promptID == nil && $0.attachmentID != nil && compatible($0.file) }
  }
  var attachmentIDs: [String] { canSend ? rows.compactMap(\.attachmentID) : [] }
  private func compatible(_ file: LocalAttachmentFile) -> Bool {
    guard let limits else { return false }
    return file.bytes <= limits.maxFileBytes && limits.inputMIMEs.contains(file.mime)
  }
  func restore() async throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
      attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.complete])
    var target = directory, resource = URLResourceValues(); resource.isExcludedFromBackup = true
    try target.setResourceValues(resource)
    disk = try await snapshots.load() ?? AttachmentDiskState()
    guard disk.drafts.count <= 1024, Set(disk.drafts.map(\.id)).count == disk.drafts.count else { throw RemoteError.invalidResponse }
    for i in disk.drafts.indices {
      try AttachmentValidation.metadata(name:disk.drafts[i].file.name,mime:disk.drafts[i].file.mime,
        bytes:disk.drafts[i].file.bytes,sha256:disk.drafts[i].file.sha256)
      if let id = disk.drafts[i].attachmentID { try AttachmentValidation.id(id) }
      guard (0...disk.drafts[i].file.bytes).contains(disk.drafts[i].receivedBytes) else { throw RemoteError.invalidResponse }
      switch disk.drafts[i].phase {
      case .allocating,.uploading: disk.drafts[i].phase = .failed
      case .committing,.sending: disk.drafts[i].phase = .uncertain
      default: break
      }
    }
    ready = true
  }
  func activate(_ value: AttachmentContext?) {
    guard context != value else { return }
    for task in tasks.values { task.cancel() }
    context = value; availability = .unsupported; limits = nil; notice = nil; accessRead = UUID(); checkingAccess = false
  }
  func refreshAccess(client: BridgeClient, context: AttachmentContext, supported: Bool) async {
    guard self.context == context else { return }
    let read = UUID(); accessRead = read
    guard supported else { availability = .unsupported; limits = nil; return }
    checkingAccess = true; limits = nil
    defer { if accessRead == read { checkingAccess = false } }
    do {
      let access = try await client.deviceAccess()
      guard self.context == context, accessRead == read else { return }
      guard access.features.fileTransfer else { availability = .needsHostGrant(.fileTransfer); limits = nil; return }
      let limits = try await client.attachmentLimits(context.key.workspaceId,context.key.sessionId)
      guard self.context == context, accessRead == read else { return }
      self.limits = limits; availability = .available; notice = nil
    } catch {
      guard self.context == context, accessRead == read else { return }
      limits = nil; availability = .unsupported
      notice = "Attachments could not be checked. Reconnect or continue on your computer."
    }
  }
  private func index(_ id: UUID) -> Int? { disk.drafts.firstIndex { $0.id == id } }
  private func draft(_ id: UUID) -> AttachmentDraft? { index(id).map { disk.drafts[$0] } }
  private func phase(_ value: AttachmentDraft.Phase, id: UUID) { if let i = index(id) { disk.drafts[i].phase = value } }
  func persist() async throws {
    guard ready else { throw RemoteError.unavailable }
    revision += 1
    try await snapshots.save(disk,revision:revision)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:directory.appending(path:"attachments.json").path)
  }
  func resetLocalData() async throws {
    activate(nil)
    ready = false
    runs.removeAll()
    for task in tasks.values { task.cancel() }
    tasks.removeAll()
    // Fence both stores before awaiting any retired network operation.
    var failures = 0
    do { try await snapshots.invalidateAndRemove() } catch { failures += 1 }
    do { try await files.invalidateAndRemove() } catch { failures += 1 }
    disk = AttachmentDiskState()
    if failures > 0 { throw RemoteError.unavailable }
  }
  func add(_ file: LocalAttachmentFile, context: AttachmentContext) async throws {
    guard self.context == context, canChoose, compatible(file), draft(file.id) == nil else { throw RemoteError.unavailable }
    guard rows.count < 4, rows.reduce(0, { $0 + $1.file.bytes }) <= AttachmentValidation.promptBytes - file.bytes else { throw RemoteError.oversized }
    try await files.verify(file)
    guard self.context == context, canChoose, compatible(file), draft(file.id) == nil, rows.count < 4,
      rows.reduce(0, { $0 + $1.file.bytes }) <= AttachmentValidation.promptBytes - file.bytes else { throw RemoteError.unavailable }
    disk.drafts.append(AttachmentDraft(key:context.key,file:file))
    do { try await persist() } catch {
      disk.drafts.removeAll { $0.id == file.id }; throw error
    }
  }
  func upload(_ id: UUID, client: BridgeClient, context: AttachmentContext) async {
    guard self.context == context, canChoose, let row = draft(id), row.key == context.key,
      [.selected,.failed].contains(row.phase), row.promptID == nil, compatible(row.file), tasks[id] == nil else { return }
    let token = UUID(); runs[id] = token
    let task = Task { await performUpload(id,client:client,context:context,token:token) }
    tasks[id] = task
    await task.value
    if runs[id] == token { tasks.removeValue(forKey:id); runs.removeValue(forKey:id) }
  }
  private func live(_ id: UUID, _ context: AttachmentContext, _ token: UUID) throws {
    guard self.context == context, runs[id] == token, !Task.isCancelled,
      let row = draft(id), ![.cancelPending,.cancelled,.attached].contains(row.phase) else { throw CancellationError() }
  }
  private func validate(_ attachment: Attachment, file: LocalAttachmentFile) throws {
    guard attachment.name == file.name, attachment.mime == file.mime, attachment.bytes == file.bytes,
      attachment.sha256 == file.sha256,
      attachment.receivedBytes == file.bytes || attachment.receivedBytes.isMultiple(of:AttachmentValidation.chunkBytes) else {
      throw RemoteError.invalidResponse
    }
  }
  private func apply(_ attachment: Attachment, id: UUID) throws {
    guard let i = index(id) else { throw RemoteError.unavailable }
    try validate(attachment,file:disk.drafts[i].file)
    guard disk.drafts[i].attachmentID == nil || disk.drafts[i].attachmentID == attachment.id else { throw RemoteError.invalidResponse }
    disk.drafts[i].attachmentID = attachment.id; disk.drafts[i].receivedBytes = attachment.receivedBytes
    guard ![.cancelPending,.cancelled].contains(disk.drafts[i].phase) else { return }
    switch attachment.state {
    case .ready: disk.drafts[i].phase = disk.drafts[i].promptID == nil ? .ready : .uncertain
    case .uploading: disk.drafts[i].phase = disk.drafts[i].promptID == nil ? .uploading : .uncertain
    case .cancelled: disk.drafts[i].phase = .cancelled
    case .expired: disk.drafts[i].phase = .expired
    case .attached: disk.drafts[i].phase = .attached
    default: disk.drafts[i].phase = .uncertain
    }
  }
  private func performUpload(_ id: UUID, client: BridgeClient, context: AttachmentContext, token: UUID) async {
    guard let row = draft(id) else { return }
    let key = context.key
    do {
      try await files.verify(row.file); try live(id,context,token)
      if let serverID = row.attachmentID {
        let value = try await client.attachment(key.workspaceId,key.sessionId,id:serverID)
        try live(id,context,token); try apply(value,id:id); try await persist()
      } else {
        phase(.allocating,id:id); try await persist(); try live(id,context,token)
        let mutation = try await client.beginAttachment(key.workspaceId,key.sessionId,name:row.file.name,
          mime:row.file.mime,bytes:row.file.bytes,sha256:row.file.sha256,requestId:row.allocationID)
        guard ["accepted","confirmed"].contains(mutation.receipt.state), let value = mutation.attachment else { throw RemoteError.outcomeUnknown }
        // Retain the old target's opaque ID even if navigation interrupted admission.
        try apply(value,id:id); try live(id,context,token); try await persist()
      }
      guard let uploaded = draft(id), let serverID = uploaded.attachmentID else { throw RemoteError.invalidResponse }
      if uploaded.phase == .ready { return }
      guard uploaded.phase == .uploading else { throw RemoteError.outcomeUnknown }
      var offset = uploaded.receivedBytes
      while offset < row.file.bytes {
        try live(id,context,token)
        let bytes = try await files.chunk(row.file,offset:offset)
        try live(id,context,token)
        let value = try await client.putAttachmentChunk(key.workspaceId,key.sessionId,id:serverID,offset:offset,bytes:bytes)
        try live(id,context,token)
        guard value.state == .uploading, value.receivedBytes == offset + bytes.count else { throw RemoteError.invalidResponse }
        try apply(value,id:id); offset = value.receivedBytes; try await persist()
      }
      phase(.committing,id:id); try await persist(); try live(id,context,token)
      let committed = try await client.commitAttachment(key.workspaceId,key.sessionId,id:serverID,sha256:row.file.sha256,requestId:row.commitID)
      try live(id,context,token)
      guard ["accepted","confirmed"].contains(committed.receipt.state), let value = committed.attachment, value.state == .ready else {
        throw RemoteError.outcomeUnknown
      }
      try apply(value,id:id); try await persist()
    } catch {
      guard let row = draft(id), ![.cancelPending,.cancelled,.attached].contains(row.phase) else { return }
      phase(row.phase == .committing || row.phase == .uncertain ? .uncertain : .failed,id:id)
      if self.context == context {
        notice = draft(id)?.phase == .uncertain
          ? "The file's status is unconfirmed. Check it before continuing; it will not be committed again automatically."
          : "Upload paused. Your selected file and message are kept. Retry when the connection is available."
      }
      try? await persist()
    }
  }
  func check(_ id: UUID, client: BridgeClient, context: AttachmentContext) async {
    guard self.context == context, let row = draft(id), row.key == context.key,
      let serverID = row.attachmentID, tasks[id] == nil else { return }
    do {
      let value = try await client.attachment(context.key.workspaceId,context.key.sessionId,id:serverID)
      guard self.context == context else { return }
      try apply(value,id:id)
      if row.promptID != nil, value.state == .ready || value.state == .uploading || value.state == .expired, let i = index(id) {
        disk.drafts[i].promptReviewed = true
      }
      try await persist()
      if value.state == .attached { try? await files.remove(row.file) }
      notice = value.state == .ready && row.promptID == nil ? "File is ready to send." : "Check this chat in OpenWork before sending again."
    } catch { if self.context == context { notice = "The file could not be checked. Keep it and try later." } }
  }
  func remove(_ id: UUID, client: BridgeClient?, context: AttachmentContext) async {
    guard self.context == context, let row = draft(id), row.key == context.key,
      row.promptID == nil || row.promptReviewed == true else { return }
    phase(.cancelPending,id:id); tasks[id]?.cancel()
    do { try await persist() } catch { notice = "Removal could not be saved. Keep the app open and try again."; return }
    if let task = tasks[id] { await task.value }
    // A lost allocation reply may have no known ID. Its host staging expires;
    // removal never creates another allocation just to look up that resource.
    if let serverID = draft(id)?.attachmentID, let client, self.context == context {
      do {
        let mutation = try await client.cancelAttachment(context.key.workspaceId,context.key.sessionId,id:serverID,requestId:row.cancelID)
        guard ["accepted","confirmed"].contains(mutation.receipt.state), mutation.attachment?.state == .cancelled else { throw RemoteError.outcomeUnknown }
        phase(.cancelled,id:id)
      } catch { if self.context == context { notice = "Removed from your message. Computer staging cleanup is unconfirmed and expires automatically; committed computer files are kept." } }
    } else { phase(.cancelled,id:id) }
    try? await files.remove(row.file); try? await persist()
  }
  func reserveSend(_ intent: SendIntent) async throws {
    guard context?.key == intent.key, canSend, attachmentIDs == intent.attachmentIds else { throw RemoteError.unavailable }
    for i in disk.drafts.indices where disk.drafts[i].key == intent.key && disk.drafts[i].phase == .ready {
      disk.drafts[i].promptID = intent.requestId; disk.drafts[i].phase = .sending
    }
    try await persist()
  }
  func finishSend(_ intent: SendIntent, accepted: Bool) async {
    var released: [LocalAttachmentFile] = []
    for i in disk.drafts.indices where disk.drafts[i].key == intent.key && disk.drafts[i].promptID == intent.requestId {
      disk.drafts[i].phase = accepted ? .attached : .uncertain
      if accepted { released.append(disk.drafts[i].file) }
    }
    do { try await persist() } catch {
      if context?.key == intent.key { notice = "Delivery status could not be saved. Check OpenWork before sending again." }
    }
    for file in released { try? await files.remove(file) }
  }
  func releaseUnsent(_ intent: SendIntent) async {
    for i in disk.drafts.indices where disk.drafts[i].key == intent.key && disk.drafts[i].promptID == intent.requestId {
      disk.drafts[i].phase = .ready; disk.drafts[i].promptID = nil
    }
    try? await persist()
  }
}
