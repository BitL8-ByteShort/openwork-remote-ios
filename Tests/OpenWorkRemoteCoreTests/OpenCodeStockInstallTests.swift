import Foundation
import Testing
@testable import OpenWorkRemoteCore

/// Test-only HTTP loopback adapter for an unmodified, isolated official binary.
/// This qualifies native DTOs and operations; it does not qualify mobile HTTPS.
private struct StockLoopbackTransport:HTTPTransport {
  let endpoint:URL
  let base=SessionTransport(profile:.openCode)
  init(_ endpoint:URL)throws {
    guard endpoint.scheme=="http",endpoint.host=="127.0.0.1",endpoint.port != nil,
      endpoint.user==nil,endpoint.password==nil,endpoint.query==nil,endpoint.fragment==nil,
      ["","/"].contains(endpoint.path) else{throw RemoteError.invalidResponse}
    self.endpoint=endpoint
  }
  private func loopback(_ request:URLRequest)throws->URLRequest {
    guard let source=request.url,source.scheme=="https",source.host=="stock-contract.invalid",
      var parts=URLComponents(url:endpoint,resolvingAgainstBaseURL:false),
      let route=URLComponents(url:source,resolvingAgainstBaseURL:false) else{throw RemoteError.invalidResponse}
    parts.percentEncodedPath=route.percentEncodedPath;parts.percentEncodedQuery=route.percentEncodedQuery
    guard let url=parts.url else{throw RemoteError.invalidResponse}
    var copy=request;copy.url=url;return copy
  }
  func data(for request:URLRequest)async throws->(Data,Int){try await data(for:request,maximumBytes:8_388_608)}
  func data(for request:URLRequest,maximumBytes:Int)async throws->(Data,Int){try await base.data(for:loopback(request),maximumBytes:maximumBytes)}
  func events(for request:URLRequest)async throws->AsyncThrowingStream<SSEFrame,any Error>{try await base.events(for:loopback(request))}
}

@Suite struct OpenCodeStockInstallTests {
  private struct Fixture:Decodable {
    let disposable:Bool
    let expectedVersion:String
    let loopback:URL
    let directory:String
    let password:String
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_STOCK_NATIVE_FIXTURE"] != nil))
  func officialStockPasswordPairingAndTypedChatContract()async throws {
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_STOCK_NATIVE_FIXTURE"])
    let bytes=try Data(contentsOf:URL(fileURLWithPath:path));#expect(bytes.count<20_000)
    let f=try JSONDecoder().decode(Fixture.self,from:bytes)
    #expect(f.disposable && f.expectedVersion=="2.0.30")
    let intentPath=URL(fileURLWithPath:path+".intent.json")
    guard !FileManager.default.fileExists(atPath:intentPath.path) else{
      Issue.record("Inspect the existing owned intent before another live run; do not replay it.");return
    }
    let transport=try StockLoopbackTransport(f.loopback)
    let origin=URL(string:"https://stock-contract.invalid")!
    let pairingClient=OpenCodePairingClient(transport:transport)
    let payload=try await pairingClient.issueUsingServerPassword(origin:origin,password:f.password)
    let paired=try await pairingClient.redeem(payload,origin:origin)
    await #expect(throws:RemoteError.unauthorized){_ = try await pairingClient.redeem(payload,origin:origin)}
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned stock qualification")
    let client=try OpenCodeClient(connection:connection,token:paired.token,transport:transport)
    #expect(try await client.info().version==f.expectedVersion)
    let location=try await client.location(directory:f.directory)
    #expect(location.directory==f.directory && location.project.canonical==f.directory)
    #expect(try await client.projects().contains{$0.id==location.project.id})
    let scope=OpenCodeLocation(directory:f.directory)
    let models=try await client.models(location:scope),agents=try await client.agents(location:scope)
    let model=try #require(models.first{$0.selectable}),agent=try #require(agents.first{$0.selectable})
    let selected=try OpenCodeModelRef(providerID:model.providerID,id:model.id)
    #expect(try await client.workspaceInfo(location:scope).provider=="git")
    _ = try await client.skills(location:scope)
    let intent=try OpenCodeNewChatIntent(connectionID:connection.id,projectID:location.project.id,directory:f.directory,model:selected,agent:agent.id)
    try JSONEncoder().encode(intent).write(to:intentPath,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:intentPath.path)
    let created=try await client.createChat(intent)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:location.project.id,sessionID:created.id,directory:f.directory)
    #expect(OpenCodeModelRef.sameSelection(created.model,selected))
    #expect(try await client.rename(target:target,title:"Owned stock contract check",expectedTitle:created.title).title=="Owned stock contract check")
    let before=try await client.session(id:created.id)
    let rules=[try OpenCodePermissionRule(action:"*",resource:"*",effect:.deny)]
    #expect(try await client.setSessionRules(target:target,rules:rules,expectedRules:before.permissions).permissions==rules)
    #expect(try await client.forms(target:target).isEmpty)
    #expect(try await client.pendingPermissions(target:target).isEmpty)
    #expect(try await client.messages(sessionID:created.id,cursor:nil).data.isEmpty)
    let prompt=try OpenCodePrompt(text:"Owned contract admission only; never execute.",resume:false)
    #expect(try await client.send(target:target,input:prompt).matches(prompt,sessionID:created.id))
    #expect(try await client.inbox(target:target).contains{$0.user?.matches(prompt,sessionID:created.id)==true})
    #expect(try await !client.activeSessions().contains(created.id))
    let tree=try await client.sessionTree(target:target);#expect(tree.sessions.count==1)
    try await client.deleteSessionTree(tree);#expect(try await client.deletedSessionTree(tree))
    let proof:[String:Bool]=["nativePasswordPairing":true,"typedReadAndWriteContract":true,"noProviderExecution":true,"ownedChatDeleted":true]
    try JSONSerialization.data(withJSONObject:proof,options:.sortedKeys).write(to:URL(fileURLWithPath:path+".result.json"),options:.atomic)
  }
}
