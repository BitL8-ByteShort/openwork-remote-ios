import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodePermissionTests {
  @Test func orderedCustomRulesArePreservedAndOnlyPermissionsArePatched() async throws {
    let transport=NativeControlsTransport(),(client,target)=try OpenCodeControlTests().setup(transport)
    let baseline=try await client.session(id:target.sessionID).permissions
    let rules=[try OpenCodePermissionRule(action:"custom.action",resource:"special/*",effect:.ask)]+(baseline ?? [])
    let result=try await client.setSessionRules(target:target,rules:rules,expectedRules:baseline)
    #expect(result.permissions==rules)
    let request=try #require(await transport.allRequests().first{$0.httpMethod=="PATCH"})
    let body=try JSONSerialization.jsonObject(with:#require(request.httpBody)) as! [String:Any]
    #expect(Set(body.keys)==["permissions"])
    #expect((body["permissions"] as? [[String:String]])?.last?["effect"]=="deny")
  }
  @Test func staleRulesCannotSilentlyDropDesktopChanges() async throws {
    let transport=NativeControlsTransport(),(client,target)=try OpenCodeControlTests().setup(transport)
    await #expect(throws:RemoteError.conflict){_ = try await client.setSessionRules(target:target,rules:[],expectedRules:nil)}
    #expect(await transport.allRequests().contains{$0.httpMethod=="PATCH"}==false)
  }
  @Test func settledPermissionIsResolvedWithoutReplayingAnApproval() async throws {
    let transport=NativeControlsTransport(),(client,target)=try OpenCodeControlTests().setup(transport)
    let pending=try await client.pendingPermissions(target:target)
    let request=try #require(pending.first)
    await transport.settle()
    #expect(try await client.replyPermission(target:target,request:request,decision:.once) == .alreadyResolved)
    #expect(await transport.allRequests().contains{$0.httpMethod=="POST"}==false)
  }
  @Test func visuallyEquivalentLinuxPatternsAreDistinctDesktopEdits() async throws {
    let transport=NativeControlsTransport(rules:[["action":"read","resource":"cafe\u{301}/*","effect":"deny"]])
    let (client,target)=try OpenCodeControlTests().setup(transport)
    let original=try OpenCodePermissionRule(action:"read",resource:"caf\u{e9}/*",effect:.deny)
    await #expect(throws:RemoteError.conflict){_ = try await client.setSessionRules(target:target,rules:[],expectedRules:[original])}
    #expect(await transport.allRequests().contains{$0.httpMethod=="PATCH"}==false)
  }
}
