import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState
private actor DefaultStoreTransport:HTTPTransport {
 var posts=0,reads=0,loss=false,denied=false,stale=false,lateDenial=false,delayed=false
 var selection:[String:Any]=["providerId":"synthetic","modelId":"a","variant":NSNull()]
 var revision=String(repeating:"a",count:64)
 var continuation:CheckedContinuation<Void,Never>?
 func configure(loss:Bool=false,denied:Bool=false,stale:Bool=false,lateDenial:Bool=false,delayed:Bool=false){self.loss=loss;self.denied=denied;self.stale=stale;self.lateDenial=lateDenial;self.delayed=delayed}
 func counts()->(Int,Int){(posts,reads)}
 func release(){continuation?.resume();continuation=nil}
 func data(for request:URLRequest) async throws ->(Data,Int){
  let value:Any
  if request.url!.path=="/v1/device/access" {value=["allWorkspaces":false,"workspaceIds":["owned"],"features":["workspaceAdministration": !denied]]}
  else if request.httpMethod=="POST" {
   posts += 1;if stale{return (Data(),409)}
   let b=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];selection=b["selection"] as! [String:Any];revision=String(repeating:"b",count:64)
   if lateDenial{return (Data(),403)};if loss{throw RemoteError.unavailable}
   value=["requestId":b["requestId"]!,"resourceId":"owned","state":"accepted","observedAt":"2026-10-09T00:00:00Z"]
  }else {
   reads += 1;if delayed{await withCheckedContinuation{continuation=$0}}
   value=["current":selection,"revision":revision,"models":[["providerId":"synthetic","modelId":"a","name":"A","variants":[]],["providerId":"synthetic","modelId":"b","name":"B","variants":["high"]]]]
  }
  return (try JSONSerialization.data(withJSONObject:["data":value,"cursor":NSNull()]),200)
 }
}
@MainActor @Suite struct WorkspaceDefaultsStoreTests {
 let choice=ModelSelection(providerId:"synthetic",modelId:"b",variant:"high")
 private func fixture()async throws ->(WorkspaceDefaultsStore,WorkspaceDefaultsContext,DefaultStoreTransport,BridgeClient,URL){
  let dir=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString),store=WorkspaceDefaultsStore(directory:dir);try await store.restore()
  let c=WorkspaceDefaultsContext(hostId:"host",workspaceId:"owned",generation:UUID());store.activate(c)
  let t=DefaultStoreTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:t)
  await store.refresh(client:client,context:c,supported:true);return (store,c,t,client,dir)
 }
 @Test func savesOnlyAfterGrantAndAuthoritativeReadback()async throws {
  let(s,c,t,client,dir)=try await fixture();defer{try? FileManager.default.removeItem(at:dir)}
  #expect(await s.save(choice,revision:s.snapshot!.revision,client:client,context:c));#expect(s.snapshot?.current==choice);#expect(s.pending==nil);#expect(await t.counts().0==1)
 }
 @Test func missingGrantAndStaleFormCannotDispatch()async throws {
  let(s,c,t,client,dir)=try await fixture();defer{try? FileManager.default.removeItem(at:dir)}
  #expect(await s.save(choice,revision:String(repeating:"f",count:64),client:client,context:c)==false);#expect(await t.counts().0==0)
  await t.configure(denied:true);await s.refresh(client:client,context:c,supported:true)
  #expect(s.availability == .needsHostGrant(.workspaceAdministration));#expect(s.snapshot==nil)
  #expect(await s.save(choice,revision:String(repeating:"a",count:64),client:client,context:c)==false);#expect(await t.counts().0==0)
 }
 @Test func knownStaleRejectionKeepsFormUsableAfterReviewAndNoUncertainIntent()async throws {
  let(s,c,t,client,dir)=try await fixture();defer{try? FileManager.default.removeItem(at:dir)}
  await t.configure(stale:true);#expect(await s.save(choice,revision:s.snapshot!.revision,client:client,context:c)==false)
  #expect(s.pending==nil);#expect(s.needsRefresh);#expect(s.notice != nil);#expect(await t.counts().0==1)
 }
 @Test func lostResponseAndLateRevocationPersistOneIntentUntilExplicitReview()async throws {
  for late in [false,true]{let(s,c,t,client,dir)=try await fixture();defer{try? FileManager.default.removeItem(at:dir)}
   await t.configure(loss: !late,lateDenial:late);#expect(await s.save(choice,revision:s.snapshot!.revision,client:client,context:c)==false)
   let rid=s.pending!.requestId;#expect(s.pending?.phase == .uncertain);#expect(!s.canEdit)
   #expect(await s.save(choice,revision:s.snapshot!.revision,client:client,context:c)==false);#expect(await t.counts().0==1)
   let reopened=WorkspaceDefaultsStore(directory:dir);try await reopened.restore();reopened.activate(c);#expect(reopened.pending?.requestId==rid)
   await t.configure();await reopened.refresh(client:client,context:c,supported:true);#expect(reopened.snapshot?.current==choice);#expect(reopened.canKeepCurrent)
   try await reopened.keepCurrent(context:c);#expect(reopened.pending==nil);#expect(await t.counts().0==1)
  }
 }
 @Test func changedWorkspaceRejectsLateReadsAndCancelNeverWrites()async throws {
  let(s,c,t,client,dir)=try await fixture();defer{try? FileManager.default.removeItem(at:dir)}
  await t.configure(delayed:true);let reading=Task{await s.refresh(client:client,context:c,supported:true)}
  while await t.counts().1<2{await Task.yield()};s.activate(WorkspaceDefaultsContext(hostId:"other",workspaceId:"foreign",generation:UUID()));await t.release();await reading.value
  #expect(s.snapshot==nil);#expect(await t.counts().0==0)
 }
}
