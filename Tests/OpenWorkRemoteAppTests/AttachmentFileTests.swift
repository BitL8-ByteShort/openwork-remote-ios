import Foundation
import CryptoKit
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite struct AttachmentFileTests {
  private func root() -> URL { FileManager.default.temporaryDirectory.appending(path: "attachment-file-tests-" + UUID().uuidString) }
  private func pdf(_ count: Int = 70) -> Data { Data(("%PDF-1.7\n" + String(repeating: "x", count: count) + "\n%%EOF\n").utf8) }
  @Test func selectedDocumentCopiesIntoPrivateBytesWithOnlyMetadataInDrafts() async throws {
    let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = folder.appending(path: "selected.pdf"), data = pdf()
    try data.write(to: source)
    let vault = ProtectedAttachmentFiles(directory: folder.appending(path: "vault"))
    let file = try await vault.importPDF(source)
    #expect(file.name == "selected.pdf")
    #expect(file.bytes == data.count)
    #expect(file.sha256 == SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    #expect(try await vault.chunk(file, offset: 0) == data)
    let encoded = String(decoding: try JSONEncoder().encode(file), as: UTF8.self)
    #expect(!encoded.contains("%PDF"))
    #expect(!encoded.contains(folder.path))
    let destination = folder.appending(path: "vault/\(file.id.uuidString.lowercased()).bin")
    let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect((try FileManager.default.attributesOfItem(atPath: destination.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
  }
  @Test func chunksAreBoundedAndRetainTheExactSelectedBytes() async throws {
    let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = folder.appending(path: "selected.pdf"), data = pdf(1_048_576 + 77)
    try data.write(to: source)
    let vault = ProtectedAttachmentFiles(directory: folder.appending(path: "vault"))
    let file = try await vault.importPDF(source)
    let first = try await vault.chunk(file, offset: 0), last = try await vault.chunk(file, offset: 1_048_576)
    #expect(first.count == 1_048_576)
    #expect(first + last == data)
    try await vault.verify(file)
  }
  @Test func falseMIMEAndQuotaFailureLeaveNoPartialFileAndKeepEarlierBytes() async throws {
    let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = folder.appending(path: "selected.pdf"), data = pdf()
    try data.write(to: source)
    let vaultRoot = folder.appending(path: "vault"), vault = ProtectedAttachmentFiles(directory: vaultRoot, quotaBytes: data.count + 1)
    let first = try await vault.importPDF(source)
    await #expect(throws: RemoteError.oversized) { try await vault.importPDF(source) }
    #expect(try await vault.chunk(first, offset: 0) == data)
    #expect(try FileManager.default.contentsOfDirectory(atPath: vaultRoot.path).count == 1)
    try Data("This is not a PDF".utf8).write(to: source)
    let other = ProtectedAttachmentFiles(directory: folder.appending(path: "other"))
    await #expect(throws: RemoteError.invalidResponse) { try await other.importPDF(source) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "other").path).isEmpty)
  }
  @Test func aReplacedSymlinkAndChangedBytesCannotUploadTheirTarget() async throws {
    let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = folder.appending(path: "selected.pdf"), data = pdf()
    try data.write(to: source)
    let vaultRoot = folder.appending(path: "vault"), vault = ProtectedAttachmentFiles(directory: vaultRoot)
    let file = try await vault.importPDF(source)
    let path = vaultRoot.appending(path: file.id.uuidString.lowercased() + ".bin")
    try FileManager.default.removeItem(at: path)
    try FileManager.default.createSymbolicLink(at: path, withDestinationURL: source)
    await #expect(throws: (any Error).self) { try await vault.chunk(file, offset: 0) }
    #expect(try Data(contentsOf: source) == data)
    try FileManager.default.removeItem(at: path)
    try Data(repeating: 0, count: data.count).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: path.path)
    await #expect(throws: RemoteError.invalidResponse) { try await vault.verify(file) }
  }
  @Test func insufficientFreeStorageRefusesCopyWithoutKeepingAPartialFile() async throws {
    let folder = root(); defer { try? FileManager.default.removeItem(at:folder) }
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let source = folder.appending(path:"selected.pdf"), data = pdf()
    try data.write(to:source)
    let vaultRoot = folder.appending(path:"vault")
    let vault = ProtectedAttachmentFiles(directory:vaultRoot,availableCapacity:{ _ in 0 })
    await #expect(throws:RemoteError.unavailable) { try await vault.importPDF(source) }
    #expect(try FileManager.default.contentsOfDirectory(atPath:vaultRoot.path).isEmpty)
    #expect(try Data(contentsOf:source) == data)
  }
}
