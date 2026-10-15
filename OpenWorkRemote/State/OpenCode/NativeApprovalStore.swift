import Foundation
import Observation
import OpenWorkRemoteCore

struct NativeApprovalContext:Hashable,Sendable {
  let target:OpenCodeTarget
  fileprivate let generation:UUID
}
enum NativeApprovalIssue {case unavailable,authenticationRequired,replyUnconfirmed,allowReviewRequired}
@MainActor @Observable final class NativeApprovalStore {
  private(set) var context:NativeApprovalContext?
  private(set) var requests:[OpenCodePermissionRequest]=[]
  private(set) var loading=false
  private(set) var replying=false
  private(set) var issue:NativeApprovalIssue?
  private(set) var alreadyResolved=false
  @ObservationIgnored private var client:(any OpenCodePermissionServing)?
  @ObservationIgnored private var readID=UUID()
  @discardableResult func activate(target:OpenCodeTarget,client:any OpenCodePermissionServing)->NativeApprovalContext {
    let value=NativeApprovalContext(target:target,generation:UUID());context=value;self.client=client
    requests=[];loading=false;replying=false;issue=nil;alreadyResolved=false;readID=UUID();return value
  }
  func deactivate(){context=nil;client=nil;requests=[];loading=false;replying=false;issue=nil;readID=UUID();alreadyResolved=false}
  @discardableResult func refresh(_ context:NativeApprovalContext) async -> Bool {
    guard self.context==context,let client else{return false}
    let id=UUID();readID=id;loading=true
    defer{if self.context==context,readID==id{loading=false}}
    do{
      let value=try await client.pendingPermissions(target:context.target)
      guard self.context==context,readID==id,!Task.isCancelled else{return false}
      requests=value;issue=nil;return true
    }catch{
      guard self.context==context,readID==id,!Task.isCancelled else{return false}
      issue=error as? RemoteError == .unauthorized ? .authenticationRequired : .unavailable;return false
    }
  }
  func reply(_ request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision,context:NativeApprovalContext,allowReviewed:Bool=false) async -> Bool {
    guard self.context==context,let client,!replying,!loading,!Task.isCancelled,
      issue==nil || issue == .allowReviewRequired,requests.contains(request) else{return false}
    if decision == .always,!allowReviewed{issue = .allowReviewRequired;return false}
    replying=true;issue=nil;alreadyResolved=false
    defer{if self.context==context{replying=false}}
    do{
      let result=try await client.replyPermission(target:context.target,request:request,decision:decision)
      guard self.context==context else{return false}
      alreadyResolved=result == .alreadyResolved
      return await refresh(context)
    }catch{
      guard self.context==context else{return false}
      await refresh(context)
      if error as? RemoteError == .unauthorized{issue = .authenticationRequired}
      else if issue != .authenticationRequired{issue = .replyUnconfirmed}
      return false
    }
  }
}
