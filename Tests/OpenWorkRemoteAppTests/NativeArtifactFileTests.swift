import Foundation
import CryptoKit
import Testing
@testable import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite struct NativeArtifactFileTests {
  private func download(_ text:String,name:String="result.txt",mime:String="text/plain",kind:OpenCodeFilePreviewKind = .text)throws->OpenCodeResultDownload{
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let file=try OpenCodeResultFile(relativePath:name,target:target),data=Data(text.utf8)
    let info=OpenCodeResultInfo(file:file,bytes:data.count,mime:mime,entityTag:"W/\"synthetic\"",previewKind:kind)
    return OpenCodeResultDownload(info:info,data:data,sha256:SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined())
  }
  @Test func nativeCopiesUseTheirOwnMetadataAndCannotCollideAcrossConnections() async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-artifacts-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let files=ProtectedArtifactFiles(directory:root)
    let first=try await files.storeNative(download("First")),second=try await files.storeNative(download("Second"))
    #expect(first.id != second.id);#expect(first.info.file.target.connectionID != second.info.file.target.connectionID)
    #expect(try await files.preview(first).text=="First")
    #expect(try await files.preview(second).text=="Second")
    try await files.verify(first);try await files.remove(first)
    #expect(try await files.preview(second).text=="Second")
  }
  @Test func htmlDisguisedAsTextIsRejectedAndLeavesNoCopy() async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-artifacts-bad-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let files=ProtectedArtifactFiles(directory:root)
    await #expect(throws:RemoteError.invalidResponse){try await files.storeNative(download("<!doctype html><html>Untrusted</html>"))}
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
  }
}
