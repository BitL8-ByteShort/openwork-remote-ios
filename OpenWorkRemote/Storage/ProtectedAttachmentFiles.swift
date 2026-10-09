import Foundation
import CryptoKit
import Darwin
import OpenWorkRemoteCore

struct LocalAttachmentFile: Codable, Sendable, Equatable, Identifiable {
  let id: UUID
  let name: String
  let mime: String
  let bytes: Int
  let sha256: String
}

/// Selected bytes live here; draft JSON contains only the opaque file ID and metadata.
actor ProtectedAttachmentFiles {
  private let directory: URL
  private let quotaBytes: Int
  init(directory: URL, quotaBytes: Int = AttachmentValidation.stagingBytes) {
    self.directory = directory.deletingLastPathComponent().resolvingSymlinksInPath()
      .appending(path: directory.lastPathComponent, directoryHint: .isDirectory)
    self.quotaBytes = min(max(quotaBytes, 1), AttachmentValidation.stagingBytes)
  }
  private func prepare() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions:0o700, .protectionKey:FileProtectionType.complete])
    let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
    guard attrs[.type] as? FileAttributeType == .typeDirectory,
      (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700,
      directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL else { throw RemoteError.invalidResponse }
    var resource = URLResourceValues(); resource.isExcludedFromBackup = true
    var target = directory; try target.setResourceValues(resource)
  }
  private func path(_ id: UUID) -> URL { directory.appending(path: id.uuidString.lowercased() + ".bin") }
  private func openRegular(_ url: URL, flags: Int32, privateFile: Bool = false) throws -> FileHandle {
    let fd = Darwin.open(url.path, flags | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
      !privateFile || (info.st_uid == getuid() && info.st_mode & 0o777 == 0o600 && info.st_nlink == 1) else {
      try? file.close(); throw RemoteError.invalidResponse
    }
    return file
  }
  private func capacity(for bytes: Int) throws {
    var used = 0
    for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      guard url.lastPathComponent.range(of: "^[0-9a-f-]{36}\\.bin$", options: .regularExpression) != nil else { continue }
      let file = try openRegular(url, flags: O_RDONLY, privateFile: true)
      defer { try? file.close() }
      let size = try file.seekToEnd()
      guard size <= UInt64(quotaBytes) else { throw RemoteError.oversized }
      used += Int(size)
      guard used <= quotaBytes else { throw RemoteError.oversized }
    }
    guard bytes <= quotaBytes - used else { throw RemoteError.oversized }
    let space = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    if let space, space >= 0, space < Int64(bytes) + 4_194_304 { throw RemoteError.unavailable }
  }
  private func validatePDF(_ file: FileHandle, bytes: Int) throws {
    try file.seek(toOffset: 0)
    let head = try file.read(upToCount: min(16, bytes)) ?? Data()
    try file.seek(toOffset: UInt64(max(0, bytes - 1024)))
    let tail = try file.read(upToCount: min(1024, bytes)) ?? Data()
    guard String(decoding: head, as: UTF8.self).range(of: "^%PDF-[12]\\.[0-9]", options: .regularExpression) != nil,
      String(decoding: tail, as: UTF8.self).range(of: "%%EOF\\s*$", options: .regularExpression) != nil else { throw RemoteError.invalidResponse }
  }
  func importPDF(_ selected: URL) throws -> LocalAttachmentFile {
    guard selected.isFileURL else { throw RemoteError.invalidResponse }
    let scoped = selected.startAccessingSecurityScopedResource()
    defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
    let source = try openRegular(selected, flags: O_RDONLY)
    defer { try? source.close() }
    let size = try source.seekToEnd()
    guard size > 0, size <= AttachmentValidation.fileBytes else { throw RemoteError.oversized }
    try source.seek(toOffset: 0)
    try prepare(); try capacity(for: Int(size))
    let id = UUID(), destination = path(id)
    let output = try openRegular(destination, flags: O_RDWR | O_CREAT | O_EXCL, privateFile: true)
    do {
      try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete, .posixPermissions:0o600], ofItemAtPath: destination.path)
      var hash = SHA256(), copied = 0
      while let data = try source.read(upToCount: 65536), !data.isEmpty {
        try Task.checkCancellation()
        copied += data.count
        guard copied <= Int(size) else { throw RemoteError.invalidResponse }
        try output.write(contentsOf: data); hash.update(data: data)
      }
      guard copied == Int(size) else { throw RemoteError.invalidResponse }
      try validatePDF(output, bytes: copied)
      let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
      try AttachmentValidation.metadata(name: selected.lastPathComponent, mime: "application/pdf", bytes: copied, sha256: digest)
      try output.synchronize(); try output.close()
      return LocalAttachmentFile(id: id, name: selected.lastPathComponent, mime: "application/pdf", bytes: copied, sha256: digest)
    } catch {
      try? output.close(); try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }
  func chunk(_ reference: LocalAttachmentFile, offset: Int) throws -> Data {
    try AttachmentValidation.metadata(name: reference.name, mime: reference.mime, bytes: reference.bytes, sha256: reference.sha256)
    guard offset >= 0, offset < reference.bytes, offset.isMultiple(of: AttachmentValidation.chunkBytes) else { throw RemoteError.invalidResponse }
    try prepare()
    let file = try openRegular(path(reference.id), flags: O_RDONLY, privateFile: true)
    defer { try? file.close() }
    guard try file.seekToEnd() == reference.bytes else { throw RemoteError.invalidResponse }
    try file.seek(toOffset: UInt64(offset))
    let data = try file.read(upToCount: min(AttachmentValidation.chunkBytes, reference.bytes - offset)) ?? Data()
    guard data.count == min(AttachmentValidation.chunkBytes, reference.bytes - offset) else { throw RemoteError.invalidResponse }
    return data
  }
  func verify(_ reference: LocalAttachmentFile) throws {
    try AttachmentValidation.metadata(name: reference.name, mime: reference.mime, bytes: reference.bytes, sha256: reference.sha256)
    try prepare()
    let file = try openRegular(path(reference.id), flags: O_RDONLY, privateFile: true)
    defer { try? file.close() }
    guard try file.seekToEnd() == reference.bytes else { throw RemoteError.invalidResponse }
    try file.seek(toOffset: 0)
    var hash = SHA256(), count = 0
    while let data = try file.read(upToCount: 65536), !data.isEmpty {
      try Task.checkCancellation(); count += data.count
      guard count <= reference.bytes else { throw RemoteError.invalidResponse }
      hash.update(data: data)
    }
    guard count == reference.bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == reference.sha256 else { throw RemoteError.invalidResponse }
  }
  func remove(_ reference: LocalAttachmentFile) throws {
    try prepare()
    let file = path(reference.id)
    if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
  }
}
