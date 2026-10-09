import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor ChangesTransport: HTTPTransport {
  var denied = false, stale = false, delayCatalog = false, delayDiff = false
  var catalogCalls = 0, diffCalls = 0
  var continuation: CheckedContinuation<Void,Never>?
  let revision = String(repeating:"a",count:64), id = "chg_"+String(repeating:"b",count:32)
  func configure(denied: Bool = false, stale: Bool = false, delayCatalog: Bool = false, delayDiff: Bool = false) {
    self.denied=denied;self.stale=stale;self.delayCatalog=delayCatalog;self.delayDiff=delayDiff
  }
  func counts() -> (Int,Int) { (catalogCalls,diffCalls) }
  func release() { continuation?.resume();continuation=nil }
  func data(for request: URLRequest) async throws -> (Data,Int) {
    let value: [String:Any]
    if request.url!.path.hasSuffix("/access") {
      value=["allWorkspaces":false,"workspaceIds":["ws_owned"],"features":["fileTransfer":!denied,"workspaceAdministration":false,"automationManagement":false]]
    } else if request.url!.path.hasSuffix("/diff") {
      diffCalls += 1; if delayDiff { await withCheckedContinuation { continuation=$0 } }
      if stale { return (Data(),409) }
      value=["revision":revision,"changeId":id,"binary":false,"text":"@@ -1 +1 @@\n-before\n+after\n","omitted":false]
    } else {
      catalogCalls += 1; if delayCatalog { await withCheckedContinuation { continuation=$0 } }
      value=["revision":revision,"sessionId":"ses_owned","provenance":"workspace","files":[["id":id,"pathLabel":"existing.txt","status":"modified","binary":false,"added":1,"removed":1]],"moreOnComputer":false]
    }
    return (try JSONSerialization.data(withJSONObject:["data":value,"cursor":NSNull()]),200)
  }
}
@MainActor @Suite struct ChangeStoreTests {
  private func context() -> ChangeContext { ChangeContext(key:DraftKey(hostId:"fixture",workspaceId:"ws_owned",sessionId:"ses_owned"),generation:UUID(),selection:UUID()) }
  private func client(_ transport: ChangesTransport) throws -> BridgeClient { try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport) }
  private func wait(_ condition: @escaping () async -> Bool) async throws {
    for _ in 0..<100 { if await condition() { return };try await Task.sleep(for:.milliseconds(5)) }
    Issue.record("Expected bounded read did not enter")
  }
  @Test func listingRequiresExplicitSelectionBeforeReadingDiffText() async throws {
    let store=ChangeStore(),c=context(),transport=ChangesTransport(),client=try client(transport)
    store.activate(c);await store.refresh(client:client,context:c,supported:true)
    #expect(store.catalog?.files.count == 1);#expect(store.availability == .available)
    #expect(await transport.counts().1 == 0)
    let ref=try #require(store.catalog?.files.first);await store.open(ref,client:client,context:c)
    #expect(store.diff?.text.contains("+after") == true);#expect(await transport.counts().1 == 1)
    store.closeDiff();#expect(store.diff == nil)
  }
  @Test func missingGrantOrCapabilityNeverListsFiles() async throws {
    let store=ChangeStore(),c=context(),transport=ChangesTransport(),client=try client(transport)
    store.activate(c);await store.refresh(client:client,context:c,supported:false)
    #expect(await transport.counts().0 == 0)
    await transport.configure(denied:true);await store.refresh(client:client,context:c,supported:true)
    #expect(store.availability == .needsHostGrant(.fileTransfer));#expect(store.catalog == nil)
    #expect(await transport.counts().0 == 0)
  }
}
extension ChangeStoreTests {
  @Test func aLateCatalogCannotPopulateAnotherChatOrPairing() async throws {
    let store=ChangeStore(),c=context(),transport=ChangesTransport(),client=try client(transport)
    await transport.configure(delayCatalog:true);store.activate(c)
    let task=Task {await store.refresh(client:client,context:c,supported:true)}
    try await wait {await transport.counts().0 == 1}
    let next=context();store.activate(next);await transport.release();await task.value
    #expect(store.context == next);#expect(store.catalog == nil);#expect(store.notice == nil)
  }
  @Test func aLateDiffAfterClosingOrBackgroundingCannotAppear() async throws {
    let store=ChangeStore(),c=context(),transport=ChangesTransport(),client=try client(transport)
    store.activate(c);await store.refresh(client:client,context:c,supported:true)
    let ref=try #require(store.catalog?.files.first);await transport.configure(delayDiff:true)
    let task=Task {await store.open(ref,client:client,context:c)}
    try await wait {await transport.counts().1 == 1}
    store.activate(nil);await transport.release();await task.value
    #expect(store.diff == nil);#expect(store.catalog == nil);#expect(store.notice == nil)
  }
  @Test func revocationBeforeOpeningAndStaleRevisionsRequireARefresh() async throws {
    for fault in ["grant","revision"] {
      let store=ChangeStore(),c=context(),transport=ChangesTransport(),client=try client(transport)
      store.activate(c);await store.refresh(client:client,context:c,supported:true)
      let ref=try #require(store.catalog?.files.first)
      await transport.configure(denied:fault == "grant",stale:fault == "revision")
      await store.open(ref,client:client,context:c)
      #expect(store.diff == nil)
      if fault == "grant" { #expect(store.availability == .needsHostGrant(.fileTransfer));#expect(await transport.counts().1 == 0) }
      else { #expect(store.needsRefresh);#expect(store.notice?.contains("Refresh") == true) }
    }
  }
}
