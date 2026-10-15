import Foundation
import CryptoKit
import Testing
@testable import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeResultService:OpenCodeResultServing {
  var downloads=0
  var changed=false
  var hold=false
  var continuation:CheckedContinuation<Void,Never>?
  let data=Data("Synthetic generated result\n".utf8)
  func holdDownload(){hold=true}
  func waitUntilHeld() async{while continuation==nil{await Task.yield()}}
  func release(){continuation?.resume();continuation=nil}
  func change(){changed=true}
  func count()->Int{downloads}
  func projectFiles(target:OpenCodeTarget,directory:String?) async throws->[OpenCodeProjectFile]{[]}
  func probeResult(_ file:OpenCodeResultFile) async throws->OpenCodeResultInfo{
    OpenCodeResultInfo(file:file,bytes:data.count,mime:"text/plain",entityTag:changed ? "W/\"changed\"":"W/\"original\"",previewKind:.text)
  }
  func downloadResult(_ info:OpenCodeResultInfo) async throws->OpenCodeResultDownload{
    downloads+=1
    if hold{await withCheckedContinuation{continuation=$0}}
    return OpenCodeResultDownload(info:info,data:data,sha256:SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined())
  }
}
@Suite @MainActor struct NativeResultStoreTests {
  @Test func downloadsRequireASelectionAndSharingRechecksTheVersion() async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-result-store-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let service=NativeResultService(),store=NativeResultStore(files:ProtectedArtifactFiles(directory:root))
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let context=store.activate(target:target,client:service)
    #expect(await service.count()==0)
    await store.open(try OpenCodeResultFile(relativePath:"result.txt",target:target),context:context)
    #expect(store.preview?.text=="Synthetic generated result\n");#expect(store.canShare)
    let url=await store.prepareShare(context:context)
    #expect(url != nil);#expect(await service.count()==1)
    await service.change()
    #expect(await store.prepareShare(context:context)==nil)
    #expect(!store.canShare)
  }
  @Test(.timeLimit(.minutes(1))) func lateResultCannotAppearInTheNextChat() async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-result-late-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let service=NativeResultService(),store=NativeResultStore(files:ProtectedArtifactFiles(directory:root))
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let context=store.activate(target:target,client:service)
    await service.holdDownload()
    let opening=Task{await store.open(try! OpenCodeResultFile(relativePath:"result.txt",target:target),context:context)}
    await service.waitUntilHeld()
    _=store.activate(target:OpenCodeTarget(connectionID:target.connectionID,projectID:"project",sessionID:"ses_other",directory:"/project"),client:service)
    await service.release();await opening.value
    #expect(store.ready==nil);#expect(store.preview==nil);#expect(!store.canShare)
  }
}
