import Foundation
import CryptoKit
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct OpenCodeLiveResultTests {
  private struct Fixture:Decodable{let pairing:String;let projectID:String;let sessionID:String;let directory:String;let nonce:String}
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_RESULTS_FIXTURE"] != nil))
  func nativeContainedResultDownloadPreviewShareAndLimits() async throws{
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_RESULTS_FIXTURE"])
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let payload=try OpenCodePairingPayload.parse(fixture.pairing),origin=try #require(payload.origins.first)
    let credential=try await OpenCodePairingClient().redeem(payload,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native result qualification")
    let client=try OpenCodeClient(connection:connection,token:credential.token)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:fixture.projectID,sessionID:fixture.sessionID,directory:fixture.directory)
    let text=Data(("PocketWork native contained result "+fixture.nonce+"\n").utf8)
    let name="Result + 日本語.txt",url=URL(fileURLWithPath:fixture.directory).appending(path:name)
    let file=try OpenCodeResultFile(toolURI:url.absoluteString,target:target)
    let entries=try await client.projectFiles(target:target,directory:nil)
    #expect(entries.contains{$0.path==name});#expect(!entries.contains{$0.path=="escape.txt"})
    let info=try await client.probeResult(file)
    #expect(info.bytes==text.count)
    #expect(try await client.downloadResult(info).data==text)
    print("Owned native result qualification: Unicode plus path, native probe and exact bytes passed")
    let cacheRoot=FileManager.default.temporaryDirectory.appending(path:"native-live-results-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:cacheRoot)}
    let store=NativeResultStore(files:ProtectedArtifactFiles(directory:cacheRoot))
    defer{store.deactivate()}
    let context=store.activate(target:target,client:client)
    await store.open(file,context:context)
    #expect(store.preview?.text==String(decoding:text,as:UTF8.self))
    let shared=try #require(await store.prepareShare(context:context))
    #expect(try Data(contentsOf:shared)==text)
    print("Owned native result qualification: protected preview and explicit share preflight passed")
    var large=Data(("PocketWork maximum contained result "+fixture.nonce+"\n").utf8)
    large.append(Data(repeating:120,count:20*1_048_576-large.count))
    let maximum=try OpenCodeResultFile(relativePath:"Maximum-result.txt",target:target)
    let maximumInfo=try await client.probeResult(maximum)
    #expect(maximumInfo.bytes==large.count)
    let downloaded=try await client.downloadResult(maximumInfo)
    #expect(downloaded.data==large)
    #expect(downloaded.sha256==SHA256.hash(data:large).map{String(format:"%02x",$0)}.joined())
    print("Owned native result qualification: twenty MiB contained download and SHA passed")
    await #expect(throws:RemoteError.oversized){try await client.probeResult(OpenCodeResultFile(relativePath:"Too-large.txt",target:target))}
    await #expect(throws:RemoteError.notFound){try await client.probeResult(OpenCodeResultFile(relativePath:"escape.txt",target:target))}
    #expect(try await !client.activeSessions().contains(target.sessionID))
    print("Owned native result qualification: over-limit probe and escaping symlink rejected; no execution")
  }
}
