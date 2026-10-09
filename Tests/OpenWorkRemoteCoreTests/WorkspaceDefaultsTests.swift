import Foundation
import Testing
@testable import OpenWorkRemoteCore
private actor DefaultsTransport:HTTPTransport {
 var requests:[URLRequest]=[];var lost=false;var wrong=false
 func configure(lost:Bool=false,wrong:Bool=false){self.lost=lost;self.wrong=wrong}
 func captured()->[URLRequest]{requests}
 func data(for request:URLRequest) async throws -> (Data,Int){
  requests.append(request);if lost{throw RemoteError.unavailable}
  let b=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
  return (try JSONSerialization.data(withJSONObject:["data":["requestId":b["requestId"]!,"resourceId":wrong ? "foreign":"owned","state":"accepted","observedAt":"2026-10-09T00:00:00Z"],"cursor":NSNull()]),200)
 }
}
@Suite struct WorkspaceDefaultsTests {
 @Test func nullableDefaultIsExplicitAndSnapshotIsClosed() throws {
  let valid:[String:Any]=["current":NSNull(),"models":[],"revision":String(repeating:"a",count:64)]
  let snapshot=try JSONDecoder().decode(WorkspaceDefaults.self,from:JSONSerialization.data(withJSONObject:valid));#expect(snapshot.current==nil)
  for key in ["current","revision"] {var b=valid;b.removeValue(forKey:key);#expect(throws:(any Error).self){try JSONDecoder().decode(WorkspaceDefaults.self,from:JSONSerialization.data(withJSONObject:b))}}
  #expect(throws:(any Error).self){try JSONDecoder().decode(WorkspaceDefaults.self,from:JSONSerialization.data(withJSONObject:valid.merging(["path":"/foreign"]){_,b in b}))}
 }
 @Test func closedStableRequestBodyTargetsWorkspaceOnly() async throws {
  let t=DefaultsTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:t),rid=UUID()
  _=try await client.setWorkspaceDefaults("owned",selection:ModelSelection(providerId:"synthetic",modelId:"b",variant:nil),revision:String(repeating:"a",count:64),requestId:rid)
  let r=await t.captured();#expect(r.count==1);#expect(r[0].url?.path=="/v1/workspaces/owned/default-model");#expect(r[0].httpMethod=="POST")
  let b=try JSONSerialization.jsonObject(with:r[0].httpBody!) as! [String:Any];#expect(Set(b.keys)==["selection","revision","requestId"]);#expect(b["requestId"] as? String==rid.uuidString.lowercased());#expect((b["selection"] as? [String:Any])?["variant"] is NSNull)
 }
 @Test func invalidInputsCannotWriteAndLostOrWrongReceiptsNeverRetry() async throws {
  let t=DefaultsTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:t),selection=ModelSelection(providerId:"synthetic",modelId:"b",variant:nil)
  await #expect(throws:(any Error).self){try await client.setWorkspaceDefaults("../foreign",selection:selection,revision:String(repeating:"a",count:64),requestId:UUID())};#expect(await t.captured().isEmpty)
  await t.configure(lost:true);await #expect(throws:RemoteError.unavailable){try await client.setWorkspaceDefaults("owned",selection:selection,revision:String(repeating:"a",count:64),requestId:UUID())};#expect(await t.captured().count==1)
  await t.configure(wrong:true);await #expect(throws:(any Error).self){try await client.setWorkspaceDefaults("owned",selection:selection,revision:String(repeating:"a",count:64),requestId:UUID())};#expect(await t.captured().count==2)
 }
}
