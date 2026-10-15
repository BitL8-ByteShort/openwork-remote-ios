import Foundation
import Observation
import OpenWorkRemoteCore

/// Creation is journaled before dispatch. Checking an uncertain outcome is read-only.
@MainActor @Observable final class NativeCreateStore {
  private(set) var ready=false
  private(set) var storageIssue=false
  private(set) var busy=false
  private(set) var reviewed=false
  private(set) var notice:String?
  private var disk=NativeCreationDisk()
  private var connectionID:ConnectionID?
  @ObservationIgnored private let persistence:any NativeCreationPersistence
  @ObservationIgnored private var client:(any OpenCodeChatServing)?
  @ObservationIgnored private var epoch=UUID()
  @ObservationIgnored private var revision:UInt64=0
  init(persistence:any NativeCreationPersistence){self.persistence=persistence}
  var pending:NativePendingCreation?{connectionID.flatMap{disk.pending[$0]}}
  var canCreate:Bool{ready && !storageIssue && !busy && pending==nil && client != nil}
  func restore()async throws{
    guard !ready else{return}
    var value=try await persistence.load();try value.validate()
    for key in value.pending.keys where value.pending[key]?.state == .prepared{value.pending[key]?.state = .unknown}
    disk=value;ready=true
  }
  func activate(connectionID:ConnectionID,client:any OpenCodeChatServing){
    epoch=UUID();self.connectionID=connectionID;self.client=client;busy=false;reviewed=false;notice=nil
  }
  func deactivate(){epoch=UUID();connectionID=nil;client=nil;busy=false;reviewed=false;notice=nil}
  func create(projectID:String,directory:String,model:OpenCodeModelRef?=nil,agent:String?=nil)async->OpenCodeSession?{
    guard canCreate,let connectionID,let client else{return nil}
    let current=epoch
    busy=true;notice=nil;reviewed=false
    defer{if current==epoch{busy=false}}
    let intent:OpenCodeNewChatIntent
    do{intent=try OpenCodeNewChatIntent(connectionID:connectionID,projectID:projectID,directory:directory,model:model,agent:agent)}
    catch{notice="Choose an existing project location before creating a chat.";return nil}
    disk.pending[connectionID]=NativePendingCreation(intent:intent,state:.prepared)
    do{try await persist()}catch{notice="The new chat request could not be saved. No request was sent.";return nil}
    // Forget or replacement during the durable write must not start a request.
    guard current==epoch,!Task.isCancelled else{
      try? await clear(intent);return nil
    }
    do{
      let session=try await client.createChat(intent)
      try await clear(intent)
      return current==epoch ? session:nil
    }catch is OpenCodeChatNotSubmitted{
      do{try await clear(intent)}catch{}
      if current==epoch{notice="The chat was not created. Reconnect or refresh the project and try again."}
    }catch{
      if disk.pending[connectionID]?.intent.id==intent.id{
        disk.pending[connectionID]?.state = .unknown;try? await persist()
      }
      if current==epoch{notice="Creation has not been confirmed. Check its status before creating another chat."}
    }
    return nil
  }
  func check()async->OpenCodeSession?{
    guard ready,!busy,let item=pending,let client else{return nil}
    let current=epoch;busy=true;notice=nil
    defer{if current==epoch{busy=false}}
    do{
      if let session=try await client.createdChat(for:item.intent){
        try await clear(item.intent)
        return current==epoch ? session:nil
      }
      if current==epoch{reviewed=true;notice="This chat was not found. It may still appear later. Review Your Chats on the computer before clearing this saved uncertainty."}
    }catch{if current==epoch{notice="The saved creation could not be checked. Keep it and reconnect before trying again."}}
    return nil
  }
  func acknowledgeUncertainty()async throws{
    guard reviewed,!busy,let item=pending else{throw RemoteError.unavailable}
    try await clear(item.intent);reviewed=false
  }
  private func clear(_ intent:OpenCodeNewChatIntent)async throws{
    guard let item=disk.pending[intent.connectionID],item.intent.id==intent.id else{return}
    disk.pending.removeValue(forKey:intent.connectionID)
    do{try await persist()}catch{
      if disk.pending[intent.connectionID]==nil{disk.pending[intent.connectionID]=item}
      throw error
    }
  }
  private func persist()async throws{
    revision &+= 1;let current=revision,value=disk
    do{try await persistence.save(value,revision:current);if current==revision{storageIssue=false}}
    catch{if current==revision{storageIssue=true};throw error}
  }
}
