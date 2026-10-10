import Foundation
import CryptoKit
import Darwin
import ImageIO
import UniformTypeIdentifiers
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
  static let shared = ProtectedAttachmentFiles(directory:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
    .appending(path:"OpenWorkRemote/AttachmentBytes",directoryHint:.isDirectory))
  private let directory: URL
  private let quotaBytes: Int
  private let availableCapacity: @Sendable (URL) throws -> Int64?
  private var retired = false
  private static func protectedAttributes(permissions: Int) -> [FileAttributeKey: Any] {
    var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
    // iOS Data Protection is required on the phone. macOS SwiftPM test hosts
    // use private POSIX permissions; macOS 15 can reject this iOS attribute.
    #if os(iOS)
    attributes[.protectionKey] = FileProtectionType.complete
    #endif
    return attributes
  }
  init(directory: URL, quotaBytes: Int = AttachmentValidation.stagingBytes,
    availableCapacity: @escaping @Sendable (URL) throws -> Int64? = {
      try $0.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }) {
    self.directory = directory.deletingLastPathComponent().resolvingSymlinksInPath()
      .appending(path: directory.lastPathComponent, directoryHint: .isDirectory)
    self.quotaBytes = min(max(quotaBytes, 1), AttachmentValidation.stagingBytes)
    self.availableCapacity = availableCapacity
  }
  private func prepare(allowRetired: Bool = false) throws {
    guard !retired || allowRetired else { throw RemoteError.cancelled }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: Self.protectedAttributes(permissions: 0o700))
    let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
    guard attrs[.type] as? FileAttributeType == .typeDirectory,
      (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700,
      directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL else { throw RemoteError.invalidResponse }
    var resource = URLResourceValues(); resource.isExcludedFromBackup = true
    var target = directory; try target.setResourceValues(resource)
  }
  func invalidateAndRemove() throws {
    retired = true
    try prepare(allowRetired: true)
    var unknown = false
    for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      guard url.lastPathComponent.range(of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\\.bin$", options: .regularExpression) != nil else { unknown = true; continue }
      let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
      guard type == .typeRegular || type == .typeSymbolicLink else { unknown = true; continue }
      try FileManager.default.removeItem(at: url)
    }
    if unknown { throw RemoteError.invalidResponse }
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
    let space = try availableCapacity(directory)
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
      try FileManager.default.setAttributes(Self.protectedAttributes(permissions: 0o600), ofItemAtPath: destination.path)
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
  /// Fresh pixels only: selected JPEG/HEIC/PNG becomes an oriented, bounded PNG.
  /// Source metadata is never passed to the destination encoder.
  func importPhoto(_ selected: URL) throws -> LocalAttachmentFile {
    try savePhotoPNG(normalizedPhoto(selected))
  }
  func normalizedPhoto(_ selected: URL) throws -> Data {
    guard selected.isFileURL else { throw RemoteError.invalidResponse }
    let scoped = selected.startAccessingSecurityScopedResource()
    defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
    let sourceFile = try openRegular(selected, flags: O_RDONLY)
    defer { try? sourceFile.close() }
    let size = try sourceFile.seekToEnd()
    guard size > 0, size <= AttachmentValidation.fileBytes else { throw RemoteError.oversized }
    try sourceFile.seek(toOffset: 0)
    var bytes = Data()
    while let chunk = try sourceFile.read(upToCount: 65536), !chunk.isEmpty {
      try Task.checkCancellation()
      guard bytes.count + chunk.count <= Int(size) else { throw RemoteError.invalidResponse }
      bytes.append(chunk)
    }
    guard bytes.count == Int(size),
      let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache:false] as CFDictionary),
      let type = CGImageSourceGetType(source) as String?,
      [UTType.jpeg.identifier, UTType.heic.identifier, UTType.png.identifier].contains(type),
      CGImageSourceGetCount(source) == 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 100_000, height <= 100_000,
      width <= 100_000_000 / height else { throw RemoteError.invalidResponse }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,
      kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceThumbnailMaxPixelSize:2048,
      kCGImageSourceShouldCacheImmediately:true]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
      image.width <= 2048, image.height <= 2048 else { throw RemoteError.invalidResponse }
    try Task.checkCancellation()
    let encoded = NSMutableData()
    guard let output = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else {
      throw RemoteError.invalidResponse
    }
    CGImageDestinationAddImage(output, image, [:] as CFDictionary)
    guard CGImageDestinationFinalize(output) else { throw RemoteError.invalidResponse }
    let png = encoded as Data
    guard !png.isEmpty, png.count <= AttachmentValidation.fileBytes else { throw RemoteError.oversized }
    return png
  }
  func savePhotoPNG(_ png: Data) throws -> LocalAttachmentFile {
    guard !png.isEmpty, png.count <= AttachmentValidation.fileBytes,
      let image = CGImageSourceCreateWithData(png as CFData,nil),
      CGImageSourceGetType(image) as String? == UTType.png.identifier,
      CGImageSourceGetCount(image) == 1 else { throw RemoteError.invalidResponse }
    try prepare(); try capacity(for: png.count); try Task.checkCancellation()
    let id = UUID(), destination = path(id)
    let file = try openRegular(destination, flags: O_WRONLY | O_CREAT | O_EXCL, privateFile: true)
    do {
      try FileManager.default.setAttributes(Self.protectedAttributes(permissions: 0o600), ofItemAtPath: destination.path)
      try file.write(contentsOf: png); try file.synchronize(); try file.close()
      let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
      return LocalAttachmentFile(id: id, name: "Photo.png", mime: "image/png", bytes: png.count, sha256: digest)
    } catch {
      try? file.close(); try? FileManager.default.removeItem(at: destination); throw error
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
