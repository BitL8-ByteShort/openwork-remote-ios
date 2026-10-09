import Foundation
import CryptoKit
import Darwin
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import OpenWorkRemoteCore

struct LocalArtifact: Sendable, Equatable, Identifiable {
  let id: UUID
  let ref: ArtifactRef
  let url: URL
}
struct ArtifactPreviewData: Sendable {
  let text: String?
  let imageURL: URL?
  let truncated: Bool
  let page: Int
  let pageCount: Int
}
/// Explicit downloads only. Originals and raster previews are transient,
/// protected and excluded from backup; no transcript or host path is cached.
actor ProtectedArtifactFiles {
  private let directory: URL
  private let quotaBytes: Int
  private let availableCapacity: @Sendable (URL) throws -> Int64?
  private var reservations: [UUID: Int] = [:]
  private var previews: [UUID: URL] = [:]
  init(directory: URL? = nil, quotaBytes: Int = 104_857_600,
       availableCapacity: @escaping @Sendable (URL) throws -> Int64? = { try $0.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage }) {
    self.directory = directory ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appending(path:"OpenWorkRemote/ArtifactDownloads",directoryHint:.isDirectory)
    self.quotaBytes = quotaBytes; self.availableCapacity = availableCapacity
  }
  private static func attributes(_ permissions: Int) -> [FileAttributeKey: Any] {
    var value: [FileAttributeKey: Any] = [.posixPermissions:permissions]
    #if os(iOS)
    value[.protectionKey] = FileProtectionType.complete
    #endif
    return value
  }
  private func prepare() throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:Self.attributes(0o700))
    let s = try info(directory)
    guard s.st_mode & S_IFMT == S_IFDIR, s.st_uid == getuid(), s.st_mode & 0o777 == 0o700,
      directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL else { throw RemoteError.invalidResponse }
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    var target = directory; try target.setResourceValues(values)
  }
  private func info(_ url: URL) throws -> stat {
    var value = stat(); guard lstat(url.path,&value) == 0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
    return value
  }
  private func openFile(_ url: URL, flags: Int32) throws -> FileHandle {
    let fd = Darwin.open(url.path,flags | O_NOFOLLOW,0o600)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
    let file = FileHandle(fileDescriptor:fd,closeOnDealloc:true); var value = stat()
    guard fstat(fd,&value) == 0, value.st_mode & S_IFMT == S_IFREG, value.st_uid == getuid(), value.st_nlink == 1, value.st_mode & 0o777 == 0o600 else {
      try? file.close(); throw RemoteError.invalidResponse
    }
    return file
  }
  private func owned(_ url: URL) -> Bool {
    url.lastPathComponent.range(of:"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}(\\.part)?$",options:.regularExpression) != nil
  }
  func cleanup() throws {
    try prepare()
    for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where owned(url) {
      if let id = UUID(uuidString:url.deletingPathExtension().lastPathComponent), reservations[id] != nil { continue }
      let s = try info(url)
      let expired = Double(s.st_mtimespec.tv_sec) < Date().timeIntervalSince1970 - 3600
      if url.pathExtension == "part" || expired || s.st_mode & S_IFMT == S_IFLNK { try FileManager.default.removeItem(at:url) }
    }
  }
  func reset() throws {
    try prepare()
    guard reservations.isEmpty else { throw RemoteError.unavailable }
    for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where owned(url) { try FileManager.default.removeItem(at:url) }
    previews.removeAll()
  }
  private func capacity(_ bytes: Int) throws {
    var used = reservations.values.reduce(0,+)
    for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where owned(url) {
      if url.pathExtension == "part", UUID(uuidString:url.deletingPathExtension().lastPathComponent).map({reservations[$0] != nil}) == true { continue }
      let s = try info(url)
      if s.st_mode & S_IFMT == S_IFREG { used += Int(s.st_size) }
      else if s.st_mode & S_IFMT == S_IFDIR {
        for child in try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil) {
          let file = try openFile(child,flags:O_RDONLY); defer { try? file.close() }
          used += Int(try file.seekToEnd())
        }
      } else { throw RemoteError.invalidResponse }
      guard used <= quotaBytes else { throw RemoteError.oversized }
    }
    guard bytes > 0, used <= quotaBytes, bytes <= quotaBytes - used else { throw RemoteError.oversized }
    if let free = try availableCapacity(directory), free >= 0, free < Int64(bytes) + 4_194_304 { throw RemoteError.unavailable }
  }
  func download(_ ref: ArtifactRef, client: BridgeClient, workspaceId: String,
                progress: @escaping @Sendable (Int) async -> Void = {_ in}) async throws -> LocalArtifact {
    try ref.validate(); try cleanup(); try capacity(ref.bytes); try Task.checkCancellation()
    let id = UUID(), partial = directory.appending(path:id.uuidString.lowercased()+".part"), folder = directory.appending(path:id.uuidString.lowercased(),directoryHint:.isDirectory)
    reservations[id] = ref.bytes
    defer { reservations[id] = nil }
    let file = try openFile(partial,flags:O_RDWR | O_CREAT | O_EXCL)
    do {
      try FileManager.default.setAttributes(Self.attributes(0o600),ofItemAtPath:partial.path)
      var offset = 0, hash = SHA256()
      while offset < ref.bytes {
        try Task.checkCancellation()
        let bytes = try await client.artifactChunk(workspaceId,ref.sessionId,ref:ref,offset:offset)
        try Task.checkCancellation()
        guard offset + bytes.count <= ref.bytes else { throw RemoteError.invalidResponse }
        try file.write(contentsOf:bytes); hash.update(data:bytes); offset += bytes.count
        await progress(offset)
      }
      guard offset == ref.bytes, hash.finalize().map({String(format:"%02x",$0)}).joined() == ref.sha256 else { throw RemoteError.invalidResponse }
      try file.synchronize(); try file.close(); try Task.checkCancellation()
      try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:Self.attributes(0o700))
      let target = folder.appending(path:ref.name)
      try FileManager.default.moveItem(at:partial,to:target)
      let ready = LocalArtifact(id:id,ref:ref,url:target)
      try validate(ready); try Task.checkCancellation()
      return ready
    } catch {
      try? file.close(); try? FileManager.default.removeItem(at:partial); try? FileManager.default.removeItem(at:folder)
      throw error
    }
  }
  private func check(_ ready: LocalArtifact) throws {
    try prepare(); try ready.ref.validate()
    let folder = directory.appending(path:ready.id.uuidString.lowercased(),directoryHint:.isDirectory)
    guard ready.url == folder.appending(path:ready.ref.name), folder.resolvingSymlinksInPath() == folder else { throw RemoteError.invalidResponse }
    let s = try info(folder)
    guard s.st_mode & S_IFMT == S_IFDIR, s.st_uid == getuid(), s.st_mode & 0o777 == 0o700 else { throw RemoteError.invalidResponse }
    let file = try openFile(ready.url,flags:O_RDONLY); defer { try? file.close() }
    guard try file.seekToEnd() == ready.ref.bytes else { throw RemoteError.invalidResponse }
  }
  private func text(_ ready: LocalArtifact) throws -> String {
    let data = try Data(contentsOf:ready.url)
    guard !data.contains(0), let text = String(data:data,encoding:.utf8), text.trimmingCharacters(in:.whitespacesAndNewlines)
      .range(of:"^(<!doctype\\s+html|<html\\b|<svg\\b|<script\\b|<\\?xml)",options:[.regularExpression,.caseInsensitive]) == nil else { throw RemoteError.invalidResponse }
    return text
  }
  private func image(_ ready: LocalArtifact) throws -> CGImage {
    if ready.ref.mime == "image/png" { try validatePNG(try Data(contentsOf:ready.url)) }
    guard let source = CGImageSourceCreateWithURL(ready.url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
      CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source).rawValue == 0,
      CGImageSourceGetType(source) as String? == (ready.ref.mime == "image/png" ? UTType.png.identifier : UTType.jpeg.identifier),
      let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
      let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 100_000, height <= 100_000, width <= 100_000_000 / height,
      let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,
        kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceShouldCacheImmediately:true] as CFDictionary),
      CGImageSourceGetStatusAtIndex(source,0).rawValue == 0 else { throw RemoteError.invalidResponse }
    return image
  }
  private static let crcTable: [UInt32] = (0..<256).map { value in
    var crc=UInt32(value)
    for _ in 0..<8 { crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1 }
    return crc
  }
  /// ImageIO can return a partial raster with a complete status when a PNG's
  /// declared IDAT overruns its file. Require complete, checksum-valid chunks
  /// before allowing ImageIO to prepare a raster or sharing the original.
  private func validatePNG(_ data: Data) throws {
    guard data.count <= 20*1024*1024, data.prefix(8) == Data([137,80,78,71,13,10,26,10]) else { throw RemoteError.invalidResponse }
    func integer(_ offset: Int) -> Int {
      (Int(data[offset]) << 24) | (Int(data[offset+1]) << 16) | (Int(data[offset+2]) << 8) | Int(data[offset+3])
    }
    var offset=8, header=false, content=false, contentEnded=false
    while offset <= data.count-12 {
      try Task.checkCancellation()
      let length=integer(offset)
      guard length <= data.count-offset-12 else { throw RemoteError.invalidResponse }
      let type=String(decoding:data[(offset+4)..<(offset+8)],as:UTF8.self)
      guard data[(offset+4)..<(offset+8)].allSatisfy({(65...90).contains($0) || (97...122).contains($0)}),
        header || (type == "IHDR" && length == 13), !["acTL","fcTL","fdAT"].contains(type) else { throw RemoteError.invalidResponse }
      var crc: UInt32=0xffffffff, count=0
      for byte in data[(offset+4)..<(offset+8+length)] {
        crc=Self.crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8);count += 1
        if count % 65536 == 0 { try Task.checkCancellation() }
      }
      guard Int(crc ^ 0xffffffff) == integer(offset+8+length) else { throw RemoteError.invalidResponse }
      if type == "IHDR" { guard !header, length == 13 else {throw RemoteError.invalidResponse};header=true }
      else if type == "IDAT" { guard !contentEnded else {throw RemoteError.invalidResponse};content=true }
      else {
        if content {contentEnded=true}
        if type == "IEND" {
          guard length == 0, content, offset+12 == data.count else {throw RemoteError.invalidResponse};return
        }
        guard type == "PLTE" || (data[offset+4] & 0x20) != 0 else {throw RemoteError.invalidResponse}
      }
      offset += length+12
    }
    throw RemoteError.invalidResponse
  }
  private func pdf(_ ready: LocalArtifact) throws -> CGPDFDocument {
    guard let provider = CGDataProvider(url:ready.url as CFURL), let doc = CGPDFDocument(provider), !doc.isEncrypted,
      (1...200).contains(doc.numberOfPages) else { throw RemoteError.invalidResponse }
    return doc
  }
  private func validate(_ ready: LocalArtifact) throws {
    try check(ready)
    switch ready.ref.previewKind {
    case .text: _ = try text(ready)
    case .image: _ = try image(ready)
    case .pdf: _ = try pdf(ready)
    case .shareOnly:
      let file = try openFile(ready.url,flags:O_RDONLY); defer { try? file.close() }
      guard String(decoding:try file.read(upToCount:16) ?? Data(),as:UTF8.self).hasPrefix("{\\rtf") else { throw RemoteError.invalidResponse }
    }
  }
  func preview(_ ready: LocalArtifact, page: Int = 1) throws -> ArtifactPreviewData {
    try check(ready); try Task.checkCancellation()
    if ready.ref.previewKind == .text {
      let value = try text(ready), bounded = String(value.prefix(100_000))
      return ArtifactPreviewData(text:bounded,imageURL:nil,truncated:value.count > bounded.count,page:1,pageCount:1)
    }
    if ready.ref.previewKind == .shareOnly { return ArtifactPreviewData(text:nil,imageURL:nil,truncated:false,page:1,pageCount:1) }
    let image: CGImage, count: Int
    if ready.ref.previewKind == .image { image = try self.image(ready); count = 1 }
    else {
      let doc = try pdf(ready); count = doc.numberOfPages
      guard page >= 1, page <= count, let pdfPage = doc.page(at:page) else { throw RemoteError.invalidResponse }
      let box = pdfPage.getBoxRect(.mediaBox)
      guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0, box.width <= 100_000, box.height <= 100_000 else { throw RemoteError.invalidResponse }
      let scale = min(1536 / max(box.width,box.height),2), width = max(1,Int(ceil(box.width * scale))), height = max(1,Int(ceil(box.height * scale)))
      guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RemoteError.unavailable }
      let rect = CGRect(x:0,y:0,width:width,height:height)
      context.setFillColor(CGColor(gray:1,alpha:1)); context.fill(rect)
      context.concatenate(pdfPage.getDrawingTransform(.mediaBox,rect:rect,rotate:0,preserveAspectRatio:true)); context.drawPDFPage(pdfPage)
      guard let result = context.makeImage() else { throw RemoteError.invalidResponse }; image = result
    }
    try Task.checkCancellation()
    let encoded = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(encoded,UTType.png.identifier as CFString,1,nil) else { throw RemoteError.unavailable }
    CGImageDestinationAddImage(destination,image,[: ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw RemoteError.invalidResponse }
    let data = encoded as Data; try capacity(data.count)
    let target = ready.url.deletingLastPathComponent().appending(path:UUID().uuidString.lowercased()+".png")
    let file = try openFile(target,flags:O_WRONLY | O_CREAT | O_EXCL)
    do {
      try FileManager.default.setAttributes(Self.attributes(0o600),ofItemAtPath:target.path)
      try file.write(contentsOf:data); try file.synchronize(); try file.close(); try Task.checkCancellation()
      if let old = previews[ready.id] { try? FileManager.default.removeItem(at:old) }; previews[ready.id] = target
      return ArtifactPreviewData(text:nil,imageURL:target,truncated:false,page:page,pageCount:count)
    } catch { try? file.close(); try? FileManager.default.removeItem(at:target); throw error }
  }
  func remove(_ ready: LocalArtifact) throws {
    try check(ready); try FileManager.default.removeItem(at:ready.url.deletingLastPathComponent()); previews[ready.id] = nil
  }
  func verify(_ ready: LocalArtifact) throws {
    try check(ready)
    let file = try openFile(ready.url,flags:O_RDONLY); defer { try? file.close() }
    var hash = SHA256(), count = 0
    while let bytes = try file.read(upToCount:65536), !bytes.isEmpty {
      try Task.checkCancellation(); count += bytes.count
      guard count <= ready.ref.bytes else { throw RemoteError.invalidResponse }; hash.update(data:bytes)
    }
    guard count == ready.ref.bytes, hash.finalize().map({String(format:"%02x",$0)}).joined() == ready.ref.sha256 else { throw RemoteError.invalidResponse }
  }
}
