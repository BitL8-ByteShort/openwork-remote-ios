import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite struct AttachmentPhotoTests {
  private func image(_ width: Int, _ height: Int) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
  }
  private func selected(_ folder: URL, type: UTType, width: Int, height: Int, orientation: Int = 1) throws -> URL {
    let url = folder.appending(path: "Selected." + (type.preferredFilenameExtension ?? "img"))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
      kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 42.123, kCGImagePropertyGPSLatitudeRef: "N"],
      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private camera note"],
      kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCreatorContactInfo: [kCGImagePropertyIPTCContactInfoEmails: "private@example.test"]]]
    CGImageDestinationAddImage(destination, try image(width, height), properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }
  @Test(arguments: [UTType.jpeg, .heic, .png])
  func selectedPhotoIsFreshPNGWithOrientationAndWithoutPrivateMetadata(type: UTType) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "photo-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = try selected(folder, type: type, width: 40, height: 20, orientation: 6)
    let original = try Data(contentsOf: source)
    if type == .jpeg || type == .heic {
      let input = try #require(CGImageSourceCreateWithData(original as CFData, nil))
      let inputProperties = try #require(CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [String: Any])
      let gps = try #require(inputProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any])
      #expect(gps[kCGImagePropertyGPSLatitude as String] as? Double == 42.123)
      let exif = try #require(inputProperties[kCGImagePropertyExifDictionary as String] as? [String: Any])
      #expect(exif[kCGImagePropertyExifUserComment as String] as? String == "private camera note")
    }
    let vault = ProtectedAttachmentFiles(directory: folder.appending(path: "vault"))
    let file = try await vault.importPhoto(source), data = try await vault.chunk(file, offset: 0)
    #expect(file.name == "Photo.png"); #expect(file.mime == "image/png")
    #expect(try Data(contentsOf: source) == original)
    let png = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetType(png) as String? == UTType.png.identifier)
    let image = try #require(CGImageSourceCreateImageAtIndex(png, 0, nil))
    #expect(image.width == 20); #expect(image.height == 40)
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(png, 0, nil) as? [String: Any])
    #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
    // ImageIO may write derived pixel/color properties. It must not copy the
    // source's private camera fields into those generated properties.
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    #expect(exif?[kCGImagePropertyExifUserComment as String] == nil)
    #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] == nil)
    #expect(properties[kCGImagePropertyIPTCDictionary as String] == nil)
    #expect(!String(decoding: data, as: UTF8.self).contains("private camera note"))
    try await vault.verify(file)
  }
  @Test func largePhotoIsDownsampledAndProtectedInsteadOfChangingTheOriginal() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "photo-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = try selected(folder, type: .jpeg, width: 3000, height: 1000)
    let vault = ProtectedAttachmentFiles(directory: folder.appending(path: "vault"))
    let file = try await vault.importPhoto(source), data = try await vault.chunk(file, offset: 0)
    let decoded = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
    #expect(image.width == 2048); #expect(image.height <= 683)
    let attributes = try FileManager.default.attributesOfItem(atPath: folder.appending(path: "vault/\(file.id.uuidString.lowercased()).bin").path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  }
  @Test func falseImageAndLowQuotaLeaveNoSelectedPhotoBytesBehind() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "photo-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "fake.jpg"); try Data("not an image".utf8).write(to: source)
    let vault = ProtectedAttachmentFiles(directory: folder.appending(path: "vault"))
    await #expect(throws: RemoteError.invalidResponse) { try await vault.importPhoto(source) }
    let photo = try selected(folder, type: .jpeg, width: 40, height: 20)
    let low = ProtectedAttachmentFiles(directory: folder.appending(path: "low"), quotaBytes: 1)
    await #expect(throws: RemoteError.oversized) { try await low.importPhoto(photo) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "low").path).isEmpty)
  }
}
