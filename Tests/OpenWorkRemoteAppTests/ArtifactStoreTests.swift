import Foundation
import CryptoKit
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor CatalogTransport: HTTPTransport {
  var denied = false, waitCatalog = false, waitBytes = false
  var changed = false
  var catalogCalls = 0, byteCalls = 0
  var continuation: CheckedContinuation<Void,Never>?
  let bytes = Data("generated result\n".utf8)
  func configure(denied: Bool = false, waitCatalog: Bool = false, waitBytes: Bool = false) { self.denied=denied;self.waitCatalog=waitCatalog;self.waitBytes=waitBytes }
  func counts() -> (Int,Int) { (catalogCalls,byteCalls) }
  func changeRevision() { changed = true }
  func release() { continuation?.resume();continuation=nil }
  func data(for request: URLRequest) async throws -> (Data,Int) {
    let value: Data
    if request.url!.path.hasSuffix("/access") {
      value=Data("{\"allWorkspaces\":false,\"workspaceIds\":[\"ws_test\"],\"features\":{\"fileTransfer\":\(!denied),\"workspaceAdministration\":false,\"automationManagement\":false}}".utf8)
    } else {
      catalogCalls += 1
      if waitCatalog { await withCheckedContinuation { continuation=$0 } }
      let hash=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
      value=try JSONSerialization.data(withJSONObject:["items":[["id":"art_"+String(repeating:"a",count:32),"sessionId":"ses_test","name":"report.txt","mime":"text/plain","bytes":bytes.count,"revision":String(repeating:changed ? "c" : "b",count:64),"sha256":hash,"previewKind":"text"]],"moreOnComputer":false])
    }
    let body = try JSONSerialization.jsonObject(with:value)
    return (try JSONSerialization.data(withJSONObject:["data":body,"cursor":NSNull()]),200)
  }
  func binary(for request: URLRequest, maximumBytes: Int) async throws -> BinaryHTTPResponse {
    byteCalls += 1
    if waitBytes { await withCheckedContinuation { continuation=$0 } }
    return BinaryHTTPResponse(data:bytes,status:206,mime:"text/plain",contentRange:"bytes 0-16/17",entityTag:"\"\(String(repeating:"b",count:64))\"",length:17)
  }
}
@MainActor @Suite struct ArtifactStoreTests {
  private func context() -> ArtifactContext { ArtifactContext(key:DraftKey(hostId:"fixture",workspaceId:"ws_test",sessionId:"ses_test"),generation:UUID(),selection:UUID()) }
  private func folder() -> URL { FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path:"result-tests-"+UUID().uuidString) }
  private func wait(_ test: @escaping () async -> Bool) async throws { for _ in 0..<100 { if await test() {return};try await Task.sleep(for:.milliseconds(10)) };Issue.record("Expected bounded operation did not enter") }
  @Test func listingDoesNotPrefetchAndPreviewRequiresExplicitSelection() async throws {
    let folder=folder();defer {try? FileManager.default.removeItem(at:folder)}
    let store=ArtifactStore(directory:folder), c=context(), transport=CatalogTransport(), client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    store.activate(c);await store.refresh(client:client,context:c,supported:true)
    #expect(store.items.count == 1);#expect(await transport.counts().1 == 0)
    let ref=try #require(store.items.first)
    await store.download(ref,client:client,context:c)
    #expect(store.preview?.text == "generated result\n");#expect(store.canShare)
    #expect(await transport.counts().1 == 1)
    store.closePreview();#expect(!store.canShare)
  }
  @Test func absentHostGrantNeverListsOrDownloadsFiles() async throws {
    let folder=folder();defer {try? FileManager.default.removeItem(at:folder)}
    let store=ArtifactStore(directory:folder),c=context(),transport=CatalogTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    await transport.configure(denied:true);store.activate(c);await store.refresh(client:client,context:c,supported:true)
    #expect(store.availability == .needsHostGrant(.fileTransfer));#expect(store.items.isEmpty);#expect(!store.canShare)
    #expect(await transport.counts().0 == 0);#expect(await transport.counts().1 == 0)
  }
  @Test func aLateCatalogCannotPopulateAnotherChatOrPairing() async throws {
    let folder=folder();defer {try? FileManager.default.removeItem(at:folder)}
    let store=ArtifactStore(directory:folder),c=context(),transport=CatalogTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    await transport.configure(waitCatalog:true);store.activate(c)
    let task=Task {await store.refresh(client:client,context:c,supported:true)}
    try await wait {await transport.counts().0 == 1}
    let next=context();store.activate(next);await transport.release();await task.value
    #expect(store.context == next);#expect(store.items.isEmpty);#expect(store.notice == nil)
  }
  @Test func aLateDownloadAfterBackgroundingCannotBecomeAVisibleOrShareableFile() async throws {
    let folder=folder();defer {try? FileManager.default.removeItem(at:folder)}
    let store=ArtifactStore(directory:folder),c=context(),transport=CatalogTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    store.activate(c);await store.refresh(client:client,context:c,supported:true)
    let ref=try #require(store.items.first);await transport.configure(waitBytes:true)
    let task=Task {await store.download(ref,client:client,context:c)}
    try await wait {await transport.counts().1 == 1}
    store.activate(nil);await transport.release();await task.value
    #expect(store.ready == nil);#expect(store.preview == nil);#expect(!store.canShare);#expect(store.notice == nil)
    #expect(await transport.counts().1 == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath:folder.appending(path:"ArtifactDownloads").path).isEmpty)
  }
  @Test func explicitShareRechecksAccessRevisionAndOriginalBytesWithoutAnotherDownload() async throws {
    for failure in ["none","grant","revision","bytes"] {
      let folder=folder();defer {try? FileManager.default.removeItem(at:folder)}
      let store=ArtifactStore(directory:folder),c=context(),transport=CatalogTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
      store.activate(c);await store.refresh(client:client,context:c,supported:true)
      await store.download(try #require(store.items.first),client:client,context:c)
      let ready=try #require(store.ready)
      if failure == "grant" { await transport.configure(denied:true) }
      if failure == "revision" { await transport.changeRevision() }
      if failure == "bytes" { try Data("changed contents\n".utf8).write(to:ready.url) }
      let url=await store.prepareShare(client:client,context:c)
      #expect((url != nil) == (failure == "none"))
      #expect(await transport.counts().1 == 1)
      if let url { #expect(try Data(contentsOf:url) == Data("generated result\n".utf8)) }
      else { #expect(!store.canShare);#expect(store.ready == nil) }
    }
  }
  @Test func aLateSharePreflightCannotHandOutAnotherChatsFile() async throws {
    let folder=folder();defer {try? FileManager.default.removeItem(at:folder)}
    let store=ArtifactStore(directory:folder),c=context(),transport=CatalogTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    store.activate(c);await store.refresh(client:client,context:c,supported:true)
    await store.download(try #require(store.items.first),client:client,context:c)
    await transport.configure(waitCatalog:true)
    let share=Task {await store.prepareShare(client:client,context:c)}
    try await wait {await transport.counts().0 == 2}
    store.activate(context());await transport.release()
    #expect(await share.value == nil);#expect(!store.canShare);#expect(store.ready == nil)
  }
  @Test func forgettingWaitsForCancelledBytesBeforeRemovingOnlyOwnedCopies() async throws {
    let folder=folder();defer {try? FileManager.default.removeItem(at:folder)}
    let store=ArtifactStore(directory:folder),c=context(),transport=CatalogTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    store.activate(c);await store.refresh(client:client,context:c,supported:true)
    let ref=try #require(store.items.first);await transport.configure(waitBytes:true)
    let download=Task {await store.download(ref,client:client,context:c)}
    try await wait {await transport.counts().1 == 1}
    let cleanup=store.discardCopies();store.activate(nil)
    #expect(!store.canShare);await transport.release();await download.value;try await cleanup.value
    #expect(try FileManager.default.contentsOfDirectory(atPath:folder.appending(path:"ArtifactDownloads").path).isEmpty)
    #expect(await transport.counts().1 == 1)
  }
}
