import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodeLiveFileTests {
  private struct Fixture:Decodable{let pairing:String;let projectID:String;let sessionID:String;let directory:String;let nonce:String}
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_FILES_FIXTURE"] != nil))
  func nativeInlineImageAndStagedPathAdmissionWithoutProviderExecution() async throws {
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_FILES_FIXTURE"])
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let payload=try OpenCodePairingPayload.parse(fixture.pairing),origin=try #require(payload.origins.first)
    let credential=try await OpenCodePairingClient().redeem(payload,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native file qualification")
    let client=try OpenCodeClient(connection:connection,token:credential.token)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:fixture.projectID,sessionID:fixture.sessionID,directory:fixture.directory)
    let models=try await client.models(location:OpenCodeLocation(directory:fixture.directory))
    let model=try #require(models.first{$0.selectable && $0.capabilities.input.contains("image")})
    let before=try await client.session(id:target.sessionID)
    _ = try await client.setModel(target:target,model:OpenCodeModelRef(providerID:model.providerID,id:model.id),expectedModel:before.model)
    print("Owned file qualification: model selection confirmed")
    let inline=try await client.prepareAttachment(bytes:Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPQCFjwHwAD1AIYT3hZ1AAAAABJRU5ErkJggg==")!,name:"inline.png",mime:"image/png",target:target,model:model)
    #expect(inline.placement == .inline)
    print("Owned file qualification: inline prepared")
    let first=try OpenCodePrompt(text:"PocketWork synthetic inline image admission",resume:false,files:[inline])
    #expect(try await client.send(target:target,input:first).matches(first,sessionID:target.sessionID))
    print("Owned file qualification: inline admitted")
    let staged=try await client.prepareAttachment(bytes:Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAB9EAAAABCAYAAABpP15DAAAAI0lEQVR4nO3DAQ0AAAgDIOMYx4hveovAxuylqqqqqqqqqmr6IMtWuJb8CXAAAAAASUVORK5CYII=")!,name:"PocketWork-qualification-"+fixture.nonce+".png",mime:"image/png",target:target,model:model)
    #expect(staged.placement == .staged)
    print("Owned file qualification: staged upload acknowledged")
    let second=try OpenCodePrompt(text:"PocketWork synthetic staged path admission",resume:false,files:[staged])
    #expect(try await client.send(target:target,input:second).matches(second,sessionID:target.sessionID))
    print("Owned file qualification: staged reference admitted")
    let inbox=try await client.inbox(target:target)
    #expect(inbox.first{$0.id==first.id}?.user?.matches(first,sessionID:target.sessionID)==true)
    #expect(inbox.first{$0.id==second.id}?.user?.matches(second,sessionID:target.sessionID)==true)
  }
}
