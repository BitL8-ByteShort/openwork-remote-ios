import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodeLiveControlTests {
  private struct Fixture:Decodable {
    let pairing:String;let projectID:String;let sessionID:String;let directory:String
    let permissionAction:String;let permissionResource:String
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_CONTROLS_FIXTURE"] != nil))
  func nativeModelsAgentsRulesAndOwnedSavedPermission() async throws {
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_CONTROLS_FIXTURE"])
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let payload=try OpenCodePairingPayload.parse(fixture.pairing),origin=try #require(payload.origins.first)
    let pairing=try await OpenCodePairingClient().redeem(payload,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native controls qualification")
    let client=try OpenCodeClient(connection:connection,token:pairing.token)
    _ = try await client.info()
    let target=OpenCodeTarget(connectionID:connection.id,projectID:fixture.projectID,sessionID:fixture.sessionID,directory:fixture.directory)
    let location=OpenCodeLocation(directory:fixture.directory)
    let agents=try await client.agents(location:location)
    let agent=try #require(agents.first{$0.selectable})
    let before=try await client.session(id:target.sessionID)
    let agentReadback=try await client.setAgent(target:target,agentID:agent.id,expectedAgent:before.agent)
    #expect(agentReadback.agent==agent.id)
    let models=try await client.models(location:location)
    let model=try #require(models.first{$0.enabled})
    let selection=try OpenCodeModelRef(providerID:model.providerID,id:model.id,variant:model.variants.first?.id)
    let modelReadback=try await client.setModel(target:target,model:selection,expectedModel:agentReadback.model)
    #expect(modelReadback.model==selection)
    let baseline=modelReadback.permissions
    let rules=(baseline ?? [])+[try OpenCodePermissionRule(action:"pocketwork_dummy_custom",resource:"owned-only/*",effect:.deny)]
    let rulesReadback=try await client.setSessionRules(target:target,rules:rules,expectedRules:baseline)
    #expect(rulesReadback.permissions==rules)
    let savedBefore=try await client.savedPermissions(target:target)
    // Test instrumentation creates its owned synthetic ask at the point of use.
    // Native asks are ephemeral and may settle while a fixture waits for compilation.
    let ask:[String:Any]=["action":fixture.permissionAction,"resources":[fixture.permissionResource],"save":[fixture.permissionResource]]
    let created=try await client.data(segments:["api","session",target.sessionID,"permission"],method:"POST",body:JSONSerialization.data(withJSONObject:ask))
    let effect=(try JSONSerialization.jsonObject(with:created) as? [String:Any])?["data"] as? [String:Any]
    #expect(effect?["effect"] as? String=="ask")
    let pending=try await client.pendingPermissions(target:target)
    let request=try #require(pending.first{$0.action==fixture.permissionAction && $0.resources==[fixture.permissionResource]})
    #expect(try await client.replyPermission(target:target,request:request,decision:.always) == .confirmed)
    let savedAfter=try await client.savedPermissions(target:target)
    let owned=savedAfter.filter{$0.action==fixture.permissionAction && $0.resource==fixture.permissionResource}
    #expect(owned.count==1)
    for grant in owned{try await client.removeSavedPermission(target:target,id:grant.id)}
    let restored=try await client.savedPermissions(target:target)
    #expect(restored.sorted{$0.id<$1.id}==savedBefore.sorted{$0.id<$1.id})
    #expect(try await client.replyPermission(target:target,request:request,decision:.reject) == .alreadyResolved)
  }
}
