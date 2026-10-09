import Foundation

extension BridgeClient {
  private func attachmentBase(_ wid: String, _ sid: String, _ value: String? = nil) throws -> String {
    let path = (try base(wid, sid)) + "/attachments"
    guard let value else { return path }
    try AttachmentValidation.id(value)
    return path + "/" + value
  }
  public func attachmentLimits(_ wid: String, _ sid: String) async throws -> AttachmentLimits {
    try await decode(Envelope<AttachmentLimits>.self, path: (try attachmentBase(wid, sid)) + "/limits").data
  }
  public func attachment(_ wid: String, _ sid: String, id: String) async throws -> Attachment {
    let value = try await decode(Envelope<Attachment>.self, path: try attachmentBase(wid, sid, id)).data
    guard value.id == id else { throw RemoteError.invalidResponse }
    return value
  }
  private func checked(_ mutation: AttachmentMutation, requestId: UUID, id: String? = nil) throws -> AttachmentMutation {
    let receipt = mutation.receipt
    guard receipt.requestId == requestId.uuidString.lowercased(),
      ["pending", "accepted", "confirmed", "rejected", "outcome_unknown"].contains(receipt.state),
      id == nil || mutation.attachment?.id == id,
      receipt.resourceId == nil || receipt.resourceId == mutation.attachment?.id,
      !["accepted", "confirmed"].contains(receipt.state) || (mutation.attachment != nil && receipt.resourceId == mutation.attachment?.id)
    else { throw RemoteError.invalidResponse }
    return mutation
  }
  public func beginAttachment(_ wid: String, _ sid: String, name: String, mime: String, bytes: Int, sha256: String, requestId: UUID) async throws -> AttachmentMutation {
    try AttachmentValidation.metadata(name: name, mime: mime, bytes: bytes, sha256: sha256)
    struct Body: Encodable { let requestId: String; let name: String; let mime: String; let bytes: Int; let sha256: String }
    let mutation = try checked(await decode(Envelope<AttachmentMutation>.self, path: try attachmentBase(wid, sid), method: "POST",
      body: JSONEncoder().encode(Body(requestId: requestId.uuidString.lowercased(), name: name, mime: mime, bytes: bytes, sha256: sha256))).data, requestId: requestId)
    if let file = mutation.attachment {
      guard file.name == name, file.mime == mime, file.bytes == bytes, file.sha256 == sha256 else { throw RemoteError.invalidResponse }
    }
    return mutation
  }
  public func putAttachmentChunk(_ wid: String, _ sid: String, id: String, offset: Int, bytes: Data) async throws -> Attachment {
    guard !bytes.isEmpty, bytes.count <= AttachmentValidation.chunkBytes, offset >= 0,
      offset <= AttachmentValidation.fileBytes - bytes.count else { throw RemoteError.oversized }
    guard offset.isMultiple(of: AttachmentValidation.chunkBytes) else { throw RemoteError.invalidResponse }
    let value = try await decode(Envelope<Attachment>.self,
      path: (try attachmentBase(wid, sid, id)) + "/chunks?offset=\(offset)", method: "PUT", body: bytes,
      contentType: "application/octet-stream").data
    guard value.id == id else { throw RemoteError.invalidResponse }
    return value
  }
  public func commitAttachment(_ wid: String, _ sid: String, id: String, sha256: String, requestId: UUID) async throws -> AttachmentMutation {
    guard sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw RemoteError.invalidResponse }
    return try checked(await decode(Envelope<AttachmentMutation>.self, path: (try attachmentBase(wid, sid, id)) + "/commit", method: "POST",
      body: JSONEncoder().encode(["requestId": requestId.uuidString.lowercased(), "sha256": sha256])).data, requestId: requestId, id: id)
  }
  public func cancelAttachment(_ wid: String, _ sid: String, id: String, requestId: UUID) async throws -> AttachmentMutation {
    try checked(await decode(Envelope<AttachmentMutation>.self, path: (try attachmentBase(wid, sid, id)) + "/cancel", method: "POST",
      body: JSONEncoder().encode(["requestId": requestId.uuidString.lowercased()])).data, requestId: requestId, id: id)
  }
  public func sendAttachments(_ wid: String, _ sid: String, text: String, attachmentIds: [String], requestId: UUID) async throws -> MutationReceipt {
    try AttachmentValidation.prompt(text: text, ids: attachmentIds)
    struct Body: Encodable { let requestId: String; let text: String; let attachmentIds: [String] }
    let receipt = try await decode(Envelope<MutationReceipt>.self, path: (try base(wid, sid)) + "/messages", method: "POST",
      body: JSONEncoder().encode(Body(requestId: requestId.uuidString.lowercased(), text: text, attachmentIds: attachmentIds))).data
    guard receipt.requestId == requestId.uuidString.lowercased(), receipt.resourceId == nil || receipt.resourceId == sid,
      ["pending", "accepted", "confirmed", "rejected", "outcome_unknown"].contains(receipt.state),
      !["accepted", "confirmed"].contains(receipt.state) || receipt.resourceId == sid else { throw RemoteError.invalidResponse }
    return receipt
  }
}
