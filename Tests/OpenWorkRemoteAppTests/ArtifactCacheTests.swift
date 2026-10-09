import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor ResultBytes: HTTPTransport {
  let bytes: Data
  let mime: String
  var pause = false
  var calls = 0
  init(_ bytes: Data, mime: String = "text/plain") { self.bytes = bytes; self.mime = mime }
  func configure(pause: Bool) { self.pause = pause }
  func count() -> Int { calls }
  func data(for request: URLRequest) async throws -> (Data, Int) { throw RemoteError.unavailable }
  func binary(for request: URLRequest, maximumBytes: Int) async throws -> BinaryHTTPResponse {
    calls += 1
    if pause { try await Task.sleep(for: .seconds(60)) }
    let range = request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-").map { Int($0)! }
    return BinaryHTTPResponse(data: bytes.subdata(in: range[0]..<range[1]+1), status: 206, mime: mime,
      contentRange: "bytes \(range[0])-\(range[1])/\(bytes.count)", entityTag: "\"\(String(repeating:"b",count:64))\"", length: maximumBytes)
  }
}
private func reference(_ data: Data, hash: String? = nil, name: String = "report.txt", mime: String = "text/plain", kind: String = "text") throws -> ArtifactRef {
  let sha = hash ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  return try JSONDecoder().decode(ArtifactRef.self, from: JSONSerialization.data(withJSONObject: [
    "id":"art_"+String(repeating:"a",count:32),"sessionId":"ses_test","name":name,"mime":mime,"bytes":data.count,
    "revision":String(repeating:"b",count:64),"sha256":sha,"previewKind":kind]))
}
private func temporary() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  return directory.resolvingSymlinksInPath()
}
@Suite struct ArtifactCacheTests {
  @Test func explicitDownloadVerifiesHashAndKeepsAProtectedNamedOriginalForSharing() async throws {
    let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }
    let data = Data("generated result\n".utf8), transport = ResultBytes(data), ref = try reference(data)
    let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport), cache = ProtectedArtifactFiles(directory:directory)
    let ready = try await cache.download(ref, client:client, workspaceId:"ws_test")
    #expect(try Data(contentsOf:ready.url) == data)
    #expect(ready.url.lastPathComponent == "report.txt")
    #expect(try FileManager.default.attributesOfItem(atPath:ready.url.path)[.posixPermissions] as? Int == 0o600)
    #expect(await transport.count() == 1)
    let preview = try await cache.preview(ready)
    #expect(preview.text == "generated result\n")
    try await cache.remove(ready)
    #expect(!FileManager.default.fileExists(atPath:ready.url.path))
  }
  @Test func checksumMismatchAndActiveOrBinaryTextNeverProduceAShareableFile() async throws {
    let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }
    let cache = ProtectedArtifactFiles(directory:directory)
    for data in [Data("valid text".utf8),Data([0,1,2]),Data("<html><script>active</script></html>".utf8)] {
      let transport = ResultBytes(data), ref = try reference(data,hash:data == Data("valid text".utf8) ? String(repeating:"0",count:64) : nil)
      let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
      await #expect(throws:(any Error).self) { try await cache.download(ref,client:client,workspaceId:"ws_test") }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
  }
  @Test func lowStorageAndCacheQuotaFailBeforeAnyNetworkRead() async throws {
    let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }
    let data = Data("result".utf8), transport = ResultBytes(data), ref = try reference(data)
    let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    for cache in [ProtectedArtifactFiles(directory:directory,quotaBytes:5),ProtectedArtifactFiles(directory:directory,availableCapacity:{_ in 0})] {
      await #expect(throws:(any Error).self) { try await cache.download(ref,client:client,workspaceId:"ws_test") }
    }
    #expect(await transport.count() == 0)
  }
  @Test func cancellationRemovesOnlyThePartialDownloadAndDoesNotRetry() async throws {
    let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }
    let data = Data("result".utf8), transport = ResultBytes(data), ref = try reference(data)
    let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport), cache = ProtectedArtifactFiles(directory:directory)
    let earlier = try await cache.download(ref,client:client,workspaceId:"ws_test")
    await transport.configure(pause:true)
    let task = Task { try await cache.download(ref,client:client,workspaceId:"ws_test") }
    for _ in 0..<100 { if await transport.count() == 2 { break }; try await Task.sleep(for:.milliseconds(10)) }
    #expect(await transport.count() == 2)
    task.cancel()
    await #expect(throws:(any Error).self) { try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath:directory.path).count == 1)
    #expect(try Data(contentsOf:earlier.url) == data)
    #expect(await transport.count() == 2)
  }
  @Test func expiryAndResetRemoveOwnedDownloadsWithoutFollowingLinksOrDeletingUnrelatedFiles() async throws {
    let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }
    let data = Data("result".utf8), transport = ResultBytes(data), ref = try reference(data)
    let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport), cache = ProtectedArtifactFiles(directory:directory)
    let ready = try await cache.download(ref,client:client,workspaceId:"ws_test")
    try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-3601)],ofItemAtPath:ready.url.deletingLastPathComponent().path)
    let keep = directory.appending(path:"keep.txt"); try data.write(to:keep)
    try FileManager.default.createSymbolicLink(at:directory.appending(path:UUID().uuidString.lowercased()+".part"),withDestinationURL:keep)
    try await cache.cleanup()
    #expect(!FileManager.default.fileExists(atPath:ready.url.path)); #expect(try Data(contentsOf:keep) == data)
    try await cache.reset()
    #expect(try Data(contentsOf:keep) == data)
  }
  @Test func multiRangeDownloadStoresExactBytesAndOnlyBoundsTheDisplayedText() async throws {
    let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }
    let data = Data(repeating:120,count:2_097_200), transport = ResultBytes(data), ref = try reference(data)
    let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport), cache = ProtectedArtifactFiles(directory:directory)
    let ready = try await cache.download(ref,client:client,workspaceId:"ws_test")
    #expect(await transport.count() == 3)
    #expect(try Data(contentsOf:ready.url) == data)
    let preview = try await cache.preview(ready)
    #expect(preview.truncated); #expect(preview.text?.count == 100_000)
  }
  @Test func corruptImagesAndPDFsAreRejectedWhileValidImagesReceiveABoundedRaster() async throws {
    let directory = try temporary(); defer { try? FileManager.default.removeItem(at:directory) }
    let encoded = NSMutableData()
    let context = try #require(CGContext(data:nil,width:32,height:16,bitsPerComponent:8,bytesPerRow:128,
      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:32,height:16))
    let destination = try #require(CGImageDestinationCreateWithData(encoded,UTType.png.identifier as CFString,1,nil))
    CGImageDestinationAddImage(destination,try #require(context.makeImage()),nil); #expect(CGImageDestinationFinalize(destination))
    let png = encoded as Data, cache = ProtectedArtifactFiles(directory:directory)
    for (data,name,mime,kind) in [(Data(png.prefix(32)),"broken.png","image/png","image"),(Data("%PDF-1.7\ninvalid\n%%EOF".utf8),"broken.pdf","application/pdf","pdf")] {
      let ref = try reference(data,name:name,mime:mime,kind:kind), transport = ResultBytes(data,mime:mime)
      let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
      await #expect(throws:RemoteError.invalidResponse) { try await cache.download(ref,client:client,workspaceId:"ws_test") }
    }
    let ref = try reference(png,name:"preview.png",mime:"image/png",kind:"image"), transport = ResultBytes(png,mime:"image/png")
    let client = try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    let ready = try await cache.download(ref,client:client,workspaceId:"ws_test"), preview = try await cache.preview(ready)
    let raster = try #require(preview.imageURL)
    #expect(try Data(contentsOf:ready.url) == png)
    let source = try #require(CGImageSourceCreateWithURL(raster as CFURL,nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source,0,nil))
    #expect(image.width == 32); #expect(image.height == 16)
  }
  @Test func PDFPagesAreBoundedRasterPreviewsAndSharingRetainsTheOriginalDocument() async throws {
    let directory=try temporary();defer {try? FileManager.default.removeItem(at:directory)}
    let encoded=NSMutableData(),consumer=try #require(CGDataConsumer(data:encoded))
    var box=CGRect(x:0,y:0,width:200,height:300)
    let writer=try #require(CGContext(consumer:consumer,mediaBox:&box,nil))
    for _ in 0..<2 { writer.beginPDFPage(nil);writer.setFillColor(CGColor(gray:0.5,alpha:1));writer.fill(box);writer.endPDFPage() }
    writer.closePDF()
    let data=encoded as Data,ref=try reference(data,name:"report.pdf",mime:"application/pdf",kind:"pdf")
    let cache=ProtectedArtifactFiles(directory:directory),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:ResultBytes(data,mime:"application/pdf"))
    let ready=try await cache.download(ref,client:client,workspaceId:"ws_test")
    let first=try await cache.preview(ready),second=try await cache.preview(ready,page:2)
    #expect(first.pageCount == 2);#expect(second.page == 2)
    #expect(!FileManager.default.fileExists(atPath:try #require(first.imageURL).path))
    let raster=try #require(second.imageURL)
    let source=try #require(CGImageSourceCreateWithURL(raster as CFURL,nil))
    let image=try #require(CGImageSourceCreateImageAtIndex(source,0,nil))
    #expect(image.width <= 1536);#expect(image.height <= 1536)
    #expect(try Data(contentsOf:ready.url) == data);try await cache.verify(ready)
    await #expect(throws:RemoteError.invalidResponse) {try await cache.preview(ready,page:3)}
  }
  @Test func PNGWithAnOverrunningChunkIsRejectedEvenWhenImageIOProducesAPartialImage() async throws {
    let folder=try #require(Bundle.module.url(forResource:"Fixtures",withExtension:nil))
    let data=try Data(contentsOf:folder.appending(path:"malformed-result.png"))
    let directory=try temporary();defer {try? FileManager.default.removeItem(at:directory)}
    let ref=try reference(data,name:"preview.png",mime:"image/png",kind:"image")
    let cache=ProtectedArtifactFiles(directory:directory),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:ResultBytes(data,mime:"image/png"))
    await #expect(throws:RemoteError.invalidResponse) { try await cache.download(ref,client:client,workspaceId:"ws_test") }
    #expect(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
  }
}
