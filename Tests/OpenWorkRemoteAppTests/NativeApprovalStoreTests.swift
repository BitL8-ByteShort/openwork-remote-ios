import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor NativeApprovalService:OpenCodePermissionServing {
  var pending:[OpenCodePermissionRequest]
  var decisions:[OpenCodePermissionDecision]=[]
  init(){pending=[try! JSONDecoder().decode(OpenCodePermissionRequest.self,from:Data(#"{"id":"prm_owned","sessionID":"ses_owned","action":"read","resources":["notes.txt"],"save":["*.txt"]}"#.utf8))]}
  func pendingPermissions(target:OpenCodeTarget) async throws -> [OpenCodePermissionRequest]{pending}
  func replyPermission(target:OpenCodeTarget,request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision) async throws -> OpenCodePermissionResolution{
    guard pending.contains(request) else{return .alreadyResolved};decisions.append(decision);pending=[];return .confirmed
  }
  func settleOnDesktop(){pending=[]}
  func replies()->Int{decisions.count}
}
@Suite @MainActor struct NativeApprovalStoreTests {
  func target()->OpenCodeTarget{OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")}
  @Test func requiredApprovalWorksWithoutAModelCatalogAndAlwaysRequiresReview() async throws {
    let service=NativeApprovalService(),store=NativeApprovalStore()
    let context=store.activate(target:target(),client:service);await store.refresh(context)
    let request=try #require(store.requests.first)
    #expect(await store.reply(request,decision:.always,context:context)==false)
    #expect(await service.replies()==0)
    #expect(await store.reply(request,decision:.always,context:context,allowReviewed:true))
    #expect(await service.replies()==1);#expect(store.requests.isEmpty)
  }
  @Test func desktopAnswerAndAnOldConnectionNeverCauseAnotherReply() async throws {
    let service=NativeApprovalService(),store=NativeApprovalStore()
    let old=store.activate(target:target(),client:service);await store.refresh(old)
    let request=try #require(store.requests.first)
    await service.settleOnDesktop()
    #expect(await store.reply(request,decision:.once,context:old))
    #expect(store.alreadyResolved);#expect(await service.replies()==0)
    let current=store.activate(target:target(),client:NativeApprovalService());await store.refresh(current)
    #expect(await store.reply(request,decision:.once,context:old)==false)
    #expect(store.requests.count==1)
  }
}
