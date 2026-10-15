import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor NativeControlService:OpenCodeControlServing {
  var selected=try! OpenCodeModelRef(providerID:"provider",id:"old")
  var rules:[OpenCodePermissionRule]=[]
  var writes=0
  var loseReply=false
  var expireOnWrite=false
  var authorizationExpired=false
  func session(id:String) async throws -> OpenCodeSession {
    if authorizationExpired{throw RemoteError.unauthorized}
    let model=try JSONSerialization.jsonObject(with:JSONEncoder().encode(selected))
    let permissions=try JSONSerialization.jsonObject(with:JSONEncoder().encode(rules))
    return try JSONDecoder().decode(OpenCodeSession.self,from:JSONSerialization.data(withJSONObject:["id":id,"projectID":"project","model":model,"permissions":permissions,"location":["directory":"/project"],"time":["created":1,"updated":2]]))
  }
  func models(location:OpenCodeLocation) async throws -> [OpenCodeModel]{[]}
  func defaultModel(location:OpenCodeLocation) async throws -> OpenCodeModel?{nil}
  func agents(location:OpenCodeLocation) async throws -> [OpenCodeAgent]{[]}
  func setModel(target:OpenCodeTarget,model:OpenCodeModelRef,expectedModel:OpenCodeModelRef?) async throws -> OpenCodeSession {
    writes+=1
    if expireOnWrite{authorizationExpired=true;throw RemoteError.unauthorized}
    selected=model;if loseReply{throw RemoteError.outcomeUnknown};return try await session(id:target.sessionID)
  }
  func setAgent(target:OpenCodeTarget,agentID:String,expectedAgent:String?) async throws -> OpenCodeSession{throw RemoteError.unavailable}
  func setSessionRules(target:OpenCodeTarget,rules:[OpenCodePermissionRule],expectedRules:[OpenCodePermissionRule]?) async throws -> OpenCodeSession {
    guard self.rules==expectedRules else{throw RemoteError.conflict}
    writes+=1;self.rules=rules;return try await session(id:target.sessionID)
  }
  func pendingPermissions(target:OpenCodeTarget) async throws -> [OpenCodePermissionRequest]{[]}
  func replyPermission(target:OpenCodeTarget,request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision) async throws -> OpenCodePermissionResolution{.confirmed}
  func savedPermissions(target:OpenCodeTarget) async throws -> [OpenCodeSavedPermission]{[]}
  func removeSavedPermission(target:OpenCodeTarget,id:String) async throws{writes+=1}
  func loseNextReply(){loseReply=true}
  func expireNextWrite(){expireOnWrite=true}
  func changeRulesOnComputer(_ value:[OpenCodePermissionRule]){rules=value}
  func writeCount()->Int{writes}
}
@Suite @MainActor struct OpenCodeControlStoreTests {
  func target()->OpenCodeTarget{OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")}
  @Test func aSheetFromAnotherConnectionCannotWriteToTheCurrentChat() async throws {
    let store=NativeControlStore(),a=NativeControlService(),b=NativeControlService()
    let old=store.activate(target:target(),client:a);await store.load(old)
    let review=try #require(store.review(old))
    let current=store.activate(target:target(),client:b);await store.load(current)
    let chosen=try OpenCodeModelRef(providerID:"provider",id:"new")
    #expect(await store.setModel(chosen,review:review)==false)
    #expect(await a.writeCount()==0);#expect(await b.writeCount()==0)
  }
  @Test func aLostWriteReplyReloadsActualDesktopStateWithoutRetrying() async throws {
    let store=NativeControlStore(),service=NativeControlService()
    let context=store.activate(target:target(),client:service);await store.load(context)
    let review=try #require(store.review(context))
    await service.loseNextReply()
    let chosen=try OpenCodeModelRef(providerID:"provider",id:"new")
    #expect(await store.setModel(chosen,review:review)==false)
    #expect(store.snapshot?.session.model?.id=="new")
    #expect(store.issue == .changeUnconfirmed)
    #expect(await service.writeCount()==1)
  }
  @Test func allowRuleNeedsReviewAndPreservesExactProposedOrder() async throws {
    let store=NativeControlStore(),service=NativeControlService()
    let context=store.activate(target:target(),client:service);await store.load(context)
    let review=try #require(store.review(context))
    let rules=[try OpenCodePermissionRule(action:"read",resource:"*",effect:.allow),try OpenCodePermissionRule(action:"read",resource:"*.env",effect:.deny)]
    #expect(await store.setRules(rules,review:review,allowReviewed:false)==false)
    #expect(store.issue == .allowReviewRequired)
    #expect(await service.writeCount()==0)
    #expect(await store.setRules(rules,review:review,allowReviewed:true))
    #expect(store.snapshot?.session.permissions==rules)
    #expect(await service.writeCount()==1)
  }
  @Test func rejectedAuthenticationStaysActionableAfterWriteRecovery() async throws {
    let store=NativeControlStore(),service=NativeControlService()
    let context=store.activate(target:target(),client:service);await store.load(context)
    let review=try #require(store.review(context))
    await service.expireNextWrite()
    let chosen=try OpenCodeModelRef(providerID:"provider",id:"new")
    #expect(await store.setModel(chosen,review:review)==false)
    #expect(store.issue == .authenticationRequired)
    #expect(await service.writeCount()==1)
  }
  @Test func backgroundRefreshCannotMakeAnOldEditOverwriteDesktopRules() async throws {
    let store=NativeControlStore(),service=NativeControlService()
    let context=store.activate(target:target(),client:service);await store.load(context)
    let review=try #require(store.review(context))
    let desktop=try OpenCodePermissionRule(action:"read",resource:"*.env",effect:.deny)
    await service.changeRulesOnComputer([desktop]);await store.load(context)
    let oldDraft=try OpenCodePermissionRule(action:"read",resource:"*",effect:.ask)
    #expect(await store.setRules([oldDraft],review:review,allowReviewed:false)==false)
    #expect(await service.writeCount()==0)
    #expect(store.snapshot?.session.permissions==[desktop])
  }
}
