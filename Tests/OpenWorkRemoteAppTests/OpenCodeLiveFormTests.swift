import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodeLiveFormTests {
  private struct Fixture:Decodable{let pairing:String;let projectID:String;let sessionID:String;let directory:String}
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_FORMS_FIXTURE"] != nil))
  func nativeOwnedFormsReplyCancelAndSettledReadback() async throws {
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_FORMS_FIXTURE"])
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let payload=try OpenCodePairingPayload.parse(fixture.pairing),origin=try #require(payload.origins.first)
    let credential=try await OpenCodePairingClient().redeem(payload,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native forms qualification")
    let client=try OpenCodeClient(connection:connection,token:credential.token)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:fixture.projectID,sessionID:fixture.sessionID,directory:fixture.directory)
    func create(_ suffix:String) async throws -> OpenCodeForm{
      let body:[String:Any]=["title":"PocketWork synthetic "+suffix,"fields":[["key":"choice","type":"string","required":true,"options":[["value":"detail","label":"Detailed"],["value":"simple","label":"Simple"]]],["key":"count","type":"integer","minimum":1,"maximum":3,"required":true,"when":[["key":"choice","op":"eq","value":"detail"]]]]]
      let bytes=try await client.data(segments:["api","session",target.sessionID,"form"],method:"POST",body:JSONSerialization.data(withJSONObject:body))
      struct Response:Decodable{let data:OpenCodeForm}
      return try JSONDecoder().decode(Response.self,from:bytes).data
    }
    let first=try await create("answer")
    let pending=try await client.forms(target:target)
    #expect(pending.contains{$0.id==first.id})
    let reviewed=try await client.form(target:target,id:first.id)
    #expect(try await client.replyForm(target:target,form:reviewed,answer:["choice":.string("detail"),"count":.number(2)]) == .confirmed)
    #expect(try await client.form(target:target,id:first.id).state?.status=="answered")
    #expect(try await client.replyForm(target:target,form:reviewed,answer:["choice":.string("simple")]) == .alreadyResolved)
    let second=try await create("cancel")
    #expect(try await client.cancelForm(target:target,form:second) == .confirmed)
    #expect(try await client.form(target:target,id:second.id).state?.status=="cancelled")
  }
}
