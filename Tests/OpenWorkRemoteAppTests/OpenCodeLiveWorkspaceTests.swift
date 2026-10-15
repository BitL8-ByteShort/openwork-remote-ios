import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeWorkspaceLiveTransport:HTTPTransport{
  let base=SessionTransport(profile:.openCode)
  let nonce:String,skillID:String
  var materialized=false
  init(nonce:String,skillID:String){self.nonce=nonce;self.skillID=skillID}
  func data(for request:URLRequest)async throws->(Data,Int){try await data(for:request,maximumBytes:8_388_608)}
  func data(for request:URLRequest,maximumBytes:Int)async throws->(Data,Int){
    let result=try await base.data(for:request,maximumBytes:maximumBytes)
    if request.url?.path.hasSuffix("/prompt")==true,result.1==200,
      let response=try? JSONSerialization.jsonObject(with:result.0) as? [String:Any],
      let row=response["data"] as? [String:Any],let payload=row["payload"] as? [String:Any],let skills=payload["skills"] as? [[String:Any]]{
      if skills.count==1{
        let actualID=skills[0]["id"] as? String,actualText=skills[0]["text"] as? String
        if actualID==skillID,let actualText,actualText.contains(nonce){materialized=true}
      }
    }
    return result
  }
  func observedMaterialization()->Bool{materialized}
}
@Suite @MainActor struct OpenCodeLiveWorkspaceTests {
  private struct Fixture:Decodable{let pairing:String;let projectID:String;let directory:String;let plainDirectory:String;let nonce:String;let createID:String;let skillID:String}
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_WORKSPACE_FIXTURE"] != nil))
  func ownedNativeWorkingCopySkillMaterializationAndLocalDefaults()async throws{
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_WORKSPACE_FIXTURE"])
    let f=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let pair=try OpenCodePairingPayload.parse(f.pairing),origin=try #require(pair.origins.first)
    let token=try await OpenCodePairingClient().redeem(pair,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native workspace qualification")
    let transport=NativeWorkspaceLiveTransport(nonce:f.nonce,skillID:f.skillID)
    let client=try OpenCodeClient(connection:connection,token:token.token,transport:transport),location=OpenCodeLocation(directory:f.directory)
    #expect(try await client.workspaceInfo(location:location).provider=="git")
    let changes=try await client.workspaceChanges(location:location)
    #expect(changes.contains{$0.file.hasSuffix("Notes + 日本語.txt")})
    #expect(changes.contains{$0.file.contains("rename")})
    #expect(changes.contains{$0.file.hasSuffix("binary.bin")})
    let diffs=try await client.workspaceDiff(location:location)
    #expect(diffs.contains{$0.file.hasSuffix("Notes + 日本語.txt") && $0.patch.contains("-old") && $0.patch.contains("+new")})
    #expect(try await client.workspaceInfo(location:OpenCodeLocation(directory:f.plainDirectory)).provider==nil)
    print("Owned native workspace: Git status/diff, Unicode path, rename/binary status and non-repository handoff passed")
    let skill=try #require(try await client.skills(location:location).first{$0.id==f.skillID})
    #expect(skill.content.contains(f.nonce))
    let models=try await client.models(location:location),agents=try await client.agents(location:location)
    let model=try #require(models.first{$0.selectable})
    let agent=agents.first{$0.id=="build" && $0.selectable} ?? agents.first{$0.selectable}
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let defaults=LocalChatDefaultsStore(persistence:try LocalChatDefaultsFile(directory:root));try await defaults.restore()
    let scope=NativeProjectKey(connectionID:connection.id,projectID:f.projectID);defaults.activate(scope)
    let value=LocalChatDefaults(model:try OpenCodeModelRef(providerID:model.providerID,id:model.id),agent:agent?.id)
    try await defaults.set(value,scope:scope,expected:LocalChatDefaults())
    let intent=try OpenCodeNewChatIntent(id:f.createID,connectionID:connection.id,projectID:f.projectID,directory:f.directory,model:defaults.value.model,agent:defaults.value.agent)
    let created=try await client.createChat(intent)
    #expect(OpenCodeModelRef.sameSelection(created.model,value.model));#expect(created.agent.map(OpenCodeIdentity.key)==value.agent.map(OpenCodeIdentity.key))
    let target=OpenCodeTarget(connectionID:connection.id,projectID:f.projectID,sessionID:created.id,directory:f.directory)
    let prompt=try OpenCodePrompt(text:"Synthetic qualification only",resume:false,skills:[skill.id])
    #expect(try await client.send(target:target,input:prompt).matches(prompt,sessionID:created.id))
    #expect(await transport.observedMaterialization())
    #expect(try await client.inbox(target:target).contains{$0.user?.matches(prompt,sessionID:created.id)==true})
    #expect(try await !client.activeSessions().contains(created.id))
    print("Owned native workspace: local model/agent defaults apply only to disposable create; synthetic skill ID and materialized text match, resume false")
    let tree=try await client.sessionTree(target:target);#expect(tree.sessions.count==1)
    try await client.deleteSessionTree(tree);#expect(try await client.deletedSessionTree(tree))
    print("Owned native workspace: disposable session deletion confirmed; no provider execution")
  }
}
