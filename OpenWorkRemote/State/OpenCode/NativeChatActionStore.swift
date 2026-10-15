import Foundation
import Observation
import OpenWorkRemoteCore

enum NativeActionResult {case fork(OpenCodeSession),deleted}
@MainActor @Observable final class NativeChatActionStore {
  private(set) var ready=false
  private(set) var storageIssue=false
  private(set) var busy=false
  private(set) var loading=false
  private(set) var reviewed=false
  private(set) var reviewedChats:[OpenCodeSession]=[]
  private(set) var target:OpenCodeTarget?
  private(set) var tree:OpenCodeSessionTree?
  private(set) var notice:String?
  private var disk=NativeActionDisk()
  @ObservationIgnored private var epoch=UUID()
  @ObservationIgnored private var revision:UInt64=0
  @ObservationIgnored private var client:(any OpenCodeTreeServing)?
  @ObservationIgnored private let persistence:any NativeActionPersistence
  init(persistence:any NativeActionPersistence){self.persistence=persistence}
  var pending:NativePendingAction?{target.flatMap{disk.pending[$0]}}
  func blocks(_ target:OpenCodeTarget)->Bool{disk.pending[target] != nil}
  func restore()async throws{
    guard !ready else{return}
    var value=try await persistence.load();try value.validate()
    for key in value.pending.keys where value.pending[key]?.state == .prepared{value.pending[key]?.state = .unknown}
    disk=value;ready=true
  }
  func activate(target:OpenCodeTarget,client:any OpenCodeTreeServing){
    epoch=UUID();self.target=target;self.client=client;busy=false;loading=false;reviewed=false;reviewedChats=[];tree=nil;notice=nil
  }
  func deactivate(){epoch=UUID();target=nil;client=nil;busy=false;loading=false;reviewed=false;reviewedChats=[];tree=nil;notice=nil}
  func loadTree()async{
    guard !busy,!loading,let target,let client else{return}
    let current=epoch;loading=true;tree=nil;notice=nil
    defer{if current==epoch{loading=false}}
    do{let result=try await client.sessionTree(target:target);if current==epoch{tree=result}}
    catch{if current==epoch{notice="The complete branch tree could not be checked. Review this chat on your computer."}}
  }
  func perform(_ action:NativeChatAction)async->NativeActionResult?{
    guard ready,!storageIssue,!busy,!loading,pending==nil,let target,let client else{return nil}
    if case .delete(let reviewed)=action{guard tree==reviewed,reviewed.target==target else{return nil}}
    let current=epoch,item=NativePendingAction(id:UUID(),target:target,action:action,state:.prepared)
    busy=true;notice=nil;reviewed=false
    defer{if current==epoch{busy=false}}
    disk.pending[target]=item
    do{try await persist()}catch{notice="The action could not be saved. No request was sent.";return nil}
    guard current==epoch,!Task.isCancelled else{try? await clear(item);return nil}
    do{
      let result:NativeActionResult
      switch action{
      case .fork(let before):result = .fork(try await client.fork(target:target,beforeMessageID:before))
      case .delete(let review):try await client.deleteSessionTree(review);result = .deleted
      }
      try await clear(item)
      return current==epoch ? result:nil
    }catch let rejected as OpenCodeChatNotSubmitted{
      try? await clear(item)
      if current==epoch{notice=rejected.reason == .conflict ? "This chat or its branches changed, or a chat is running. Refresh and review the action again.":"The action was rejected. Refresh or reconnect before trying again.";tree=nil}
    }catch{
      if disk.pending[target]?.id==item.id{disk.pending[target]?.state = .unknown;try? await persist()}
      if current==epoch{notice="The action has not been confirmed. Check the computer before trying another action."}
    }
    return nil
  }
  func checkDeletion()async->Bool{
    guard !busy,let item=pending,case .delete(let review)=item.action,let client else{return false}
    let current=epoch;busy=true;defer{if current==epoch{busy=false}}
    do{
      if try await client.deletedSessionTree(review){try await clear(item);return current==epoch}
      if current==epoch{notice="At least one reviewed chat still exists. Review the computer before clearing the saved uncertainty."}
    }catch{if current==epoch{notice="Deletion could not be checked. Reconnect and check again."}}
    return false
  }
  /// Called only after a successful recent-chat read and deliberate user review.
  func markReviewed(_ rows:[OpenCodeSession]=[]){guard !busy,pending != nil else{return};reviewedChats=Array(rows.prefix(50));reviewed=true}
  func keepCurrentChats()async throws{
    guard reviewed,!busy,let item=pending else{throw RemoteError.unavailable}
    try await clear(item);reviewed=false
  }
  private func clear(_ item:NativePendingAction)async throws{
    guard disk.pending[item.target]?.id==item.id else{return}
    disk.pending.removeValue(forKey:item.target)
    do{try await persist()}catch{if disk.pending[item.target]==nil{disk.pending[item.target]=item};throw error}
  }
  private func persist()async throws{
    revision &+= 1;let current=revision,value=disk
    do{try await persistence.save(value,revision:current);if current==revision{storageIssue=false}}
    catch{if current==revision{storageIssue=true};throw error}
  }
}
