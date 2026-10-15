import Foundation
import Observation
import OpenWorkRemoteCore

/// A local view identity, never a native server revision or lock.
struct NativeControlContext:Hashable,Sendable {
  let target:OpenCodeTarget
  fileprivate let generation:UUID
}
/// Captured when editing starts, so later refreshes cannot change the precondition.
struct NativeControlReview:Sendable {
  let context:NativeControlContext
  let session:OpenCodeSession
  fileprivate init(context:NativeControlContext,session:OpenCodeSession){self.context=context;self.session=session}
}
struct NativeControlSnapshot:Sendable {
  let session:OpenCodeSession
  let models:[OpenCodeModel]
  let agents:[OpenCodeAgent]
  let serverDefault:OpenCodeModel?
  let requests:[OpenCodePermissionRequest]
  let saved:[OpenCodeSavedPermission]
}
enum NativeControlIssue{case unavailable,authenticationRequired,changeUnconfirmed,allowReviewRequired,locationChanged}
@MainActor @Observable final class NativeControlStore {
  private(set) var context:NativeControlContext?
  private(set) var snapshot:NativeControlSnapshot?
  private(set) var loading=false
  private(set) var busy=false
  private(set) var issue:NativeControlIssue?
  private(set) var requestAlreadyResolved=false
  @ObservationIgnored private var client:(any OpenCodeControlServing)?
  @ObservationIgnored private var readID=UUID()
  @discardableResult func activate(target:OpenCodeTarget,client:any OpenCodeControlServing)->NativeControlContext {
    let context=NativeControlContext(target:target,generation:UUID())
    self.context=context;self.client=client;snapshot=nil;loading=false;busy=false;issue=nil;requestAlreadyResolved=false;readID=UUID()
    return context
  }
  func deactivate(){context=nil;client=nil;snapshot=nil;loading=false;busy=false;issue=nil;requestAlreadyResolved=false;readID=UUID()}
  @discardableResult func load(_ context:NativeControlContext) async -> Bool {
    guard self.context==context,let client else{return false}
    let id=UUID();readID=id;loading=true
    defer{if self.context==context,readID==id{loading=false}}
    let target=context.target,location=OpenCodeLocation(directory:context.target.directory)
    do{
      async let session=client.session(id:target.sessionID)
      async let models=client.models(location:location)
      async let agents=client.agents(location:location)
      async let defaultModel=client.defaultModel(location:location)
      async let requests=client.pendingPermissions(target:target)
      async let saved=client.savedPermissions(target:target)
      let (actual,catalog,registered,defaultValue,pending,grants)=try await (session,models,agents,defaultModel,requests,saved)
      guard self.context==context,readID==id,!Task.isCancelled else{return false}
      guard actual.id==target.sessionID,actual.projectID==target.projectID,OpenCodeIdentity.matches(actual.location.directory,target.directory),
        actual.time.archived==nil else{issue = .locationChanged;return false}
      snapshot=NativeControlSnapshot(session:actual,models:catalog,agents:registered,serverDefault:defaultValue,requests:pending,saved:grants)
      issue=nil
      return true
    }catch{
      guard self.context==context,readID==id,!Task.isCancelled else{return false}
      issue=error as? RemoteError == .unauthorized ? .authenticationRequired : .unavailable
      return false
    }
  }
  func canEdit(_ context:NativeControlContext)->Bool {
    self.context==context && snapshot != nil && !loading && !busy && (issue==nil || issue == .allowReviewRequired)
  }
  func review(_ context:NativeControlContext)->NativeControlReview? {
    guard canEdit(context),let session=snapshot?.session else{return nil}
    return NativeControlReview(context:context,session:session)
  }
  func setModel(_ ref:OpenCodeModelRef,review:NativeControlReview) async -> Bool {
    let context=review.context,before=review.session
    guard canEdit(context),let client else{return false}
    return await mutate(context){_ = try await client.setModel(target:context.target,model:ref,expectedModel:before.model)}
  }
  func setAgent(_ id:String,review:NativeControlReview) async -> Bool {
    let context=review.context,before=review.session
    guard canEdit(context),let client else{return false}
    return await mutate(context){_ = try await client.setAgent(target:context.target,agentID:id,expectedAgent:before.agent)}
  }
  func setRules(_ rules:[OpenCodePermissionRule],review:NativeControlReview,allowReviewed:Bool) async -> Bool {
    let context=review.context,before=review.session
    guard canEdit(context),let client else{return false}
    if rules != before.permissions,rules.contains(where:{$0.effect == .allow}),!allowReviewed{issue = .allowReviewRequired;return false}
    return await mutate(context){_ = try await client.setSessionRules(target:context.target,rules:rules,expectedRules:before.permissions)}
  }
  func reply(_ request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision,
             context:NativeControlContext,allowReviewed:Bool=false) async -> Bool {
    guard canEdit(context),let client else{return false}
    if decision == .always,!allowReviewed{issue = .allowReviewRequired;return false}
    return await mutate(context){
      let result=try await client.replyPermission(target:context.target,request:request,decision:decision)
      if self.context==context{self.requestAlreadyResolved=result == .alreadyResolved}
    }
  }
  func removeSaved(_ id:String,context:NativeControlContext) async -> Bool {
    guard canEdit(context),let client else{return false}
    return await mutate(context){try await client.removeSavedPermission(target:context.target,id:id)}
  }
  private func mutate(_ context:NativeControlContext,operation:() async throws -> Void) async -> Bool {
    guard self.context==context,!busy,!Task.isCancelled else{return false}
    busy=true;issue=nil;requestAlreadyResolved=false
    defer{if self.context==context{busy=false}}
    do{
      try await operation()
      guard self.context==context else{return false}
      return await load(context)
    }catch{
      guard self.context==context else{return false}
      // Never retry a write. A lost acknowledgement can follow a successful save.
      await load(context)
      if self.context==context,issue != .authenticationRequired,issue != .locationChanged{issue = .changeUnconfirmed}
      return false
    }
  }
}
