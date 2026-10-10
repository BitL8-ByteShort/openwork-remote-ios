import Foundation
import Observation
import OpenWorkRemoteCore
struct WorkspaceDefaultsContext:Equatable,Sendable{let hostId:String,workspaceId:String,generation:UUID}
struct WorkspaceDefaultIntent:Codable,Sendable {
 enum Phase:String,Codable,Sendable{case sending,uncertain}
 let hostId:String,workspaceId:String,requestId:UUID,revision:String,selection:ModelSelection
 var phase:Phase
}
private struct DefaultsDisk:Codable,Sendable{var intents:[WorkspaceDefaultIntent]=[]}
@MainActor @Observable final class WorkspaceDefaultsStore {
 private(set) var context:WorkspaceDefaultsContext?
 private(set) var snapshot:WorkspaceDefaults?
 private(set) var availability:FeatureAvailability = .unsupported
 private(set) var loading=false
 private(set) var needsRefresh=false
 private(set) var ready=false
 private(set) var reviewed=false
 private(set) var notice:String?
 private var disk=DefaultsDisk()
 private var version:UInt64=0
 private let directory:URL,persistence:RevisionedSnapshotStore<DefaultsDisk>
 @ObservationIgnored private var readID=UUID()
 @ObservationIgnored private var readTask:Task<WorkspaceDefaults,any Error>?
 init(directory:URL?=nil){self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appending(path:"OpenWorkRemote",directoryHint:.isDirectory);persistence=RevisionedSnapshotStore(url:self.directory.appending(path:"workspace-defaults.json"))}
 var pending:WorkspaceDefaultIntent? {guard let c=context else{return nil};return disk.intents.first{$0.hostId==c.hostId && $0.workspaceId==c.workspaceId}}
 var saving:Bool{pending?.phase == .sending}
 var canEdit:Bool{ready && !loading && availability == .available && snapshot != nil && !needsRefresh && pending==nil}
 var canKeepCurrent:Bool{pending?.phase == .uncertain && reviewed && !needsRefresh}
 func restore() async throws {
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
  disk=try await persistence.load() ?? DefaultsDisk();guard disk.intents.count<=100 else{throw RemoteError.oversized}
  for n in disk.intents.indices{disk.intents[n].phase = .uncertain};ready=true
 }
 private func persist() async throws{version += 1;try await persistence.save(disk,revision:version)}
 func resetLocalData() async throws{activate(nil);ready=false;try await persistence.invalidateAndRemove();disk=DefaultsDisk()}
 private func remove(_ id:UUID){disk.intents.removeAll{$0.requestId==id}}
 func activate(_ c:WorkspaceDefaultsContext?){guard context != c else{return};readID=UUID();readTask?.cancel();readTask=nil;context=c;snapshot=nil;availability = .unsupported;loading=false;needsRefresh=false;notice=nil;reviewed=false}
 private func allowed(_ client:BridgeClient,_ c:WorkspaceDefaultsContext) async throws {
  let access=try await client.deviceAccess()
  guard access.allWorkspaces || access.workspaceIds.contains(c.workspaceId),access.features.workspaceAdministration else{throw RemoteError.forbidden}
 }
 func refresh(client:BridgeClient,context c:WorkspaceDefaultsContext,supported:Bool) async {
  guard context==c,!saving else{return};readTask?.cancel();let run=UUID();readID=run
  guard supported else{snapshot=nil;availability = .unsupported;loading=false;readTask=nil;return}
  loading=true
  let task=Task{try await self.allowed(client,c);return try await client.workspaceDefaults(c.workspaceId)};readTask=task
  defer{if readID==run{loading=false;readTask=nil}}
  do {
   let value=try await withTaskCancellationHandler{try await task.value}onCancel:{task.cancel()}
   guard context==c,readID==run,!Task.isCancelled else{return}
   snapshot=value;availability = .available;needsRefresh=false;notice=nil;reviewed=pending?.phase == .uncertain
  }catch {
   guard context==c,readID==run,!Task.isCancelled else{return};needsRefresh=true
   if (error as? RemoteError) == .forbidden {snapshot=nil;availability = .needsHostGrant(.workspaceAdministration);notice="Allow workspace administration for this phone in Remote access on your computer."}
   else if (error as? RemoteError) == .incompatible {snapshot=nil;availability = .unsupported;notice="Default model editing is unavailable on this computer. Update OpenWork Remote Preview or change it on your computer."}
   else{notice="The workspace default could not be checked. Your selection is kept; reconnect and refresh."}
  }
 }
 func save(_ selection:ModelSelection,revision:String,client:BridgeClient,context c:WorkspaceDefaultsContext) async->Bool {
  guard context==c,canEdit,let snapshot else{return false}
  guard revision==snapshot.revision else{notice="The default changed while this form was open. Review the current default before saving.";return false}
  guard snapshot.supports(selection) else{notice="This model or reasoning level is no longer available. Refresh available models.";return false}
  guard disk.intents.count<100 else{notice="Review earlier unconfirmed default changes before saving another.";return false}
  let intent=WorkspaceDefaultIntent(hostId:c.hostId,workspaceId:c.workspaceId,requestId:UUID(),revision:revision,selection:selection,phase:.sending)
  disk.intents.append(intent);notice=nil;reviewed=false
  do{try await persist()}catch{remove(intent.requestId);ready=false;notice="The change could not be saved safely. Continue on your computer.";return false}
  var dispatched=false
  do {
   try await allowed(client,c);guard context==c,!Task.isCancelled else{throw RemoteError.cancelled}
   dispatched=true
   let receipt=try await client.setWorkspaceDefaults(c.workspaceId,selection:selection,revision:revision,requestId:intent.requestId)
   guard ["accepted","confirmed"].contains(receipt.state) else{throw RemoteError.outcomeUnknown}
   let actual=try await client.workspaceDefaults(c.workspaceId);try await allowed(client,c)
   guard context==c,!Task.isCancelled,actual.current==selection else{throw RemoteError.outcomeUnknown}
   self.snapshot=actual;remove(intent.requestId);try await persist();needsRefresh=false;return true
  }catch {
   // A 403 after dispatch can also be late revocation following a successful PUT.
   let known = !dispatched || (error as? RemoteError) == .conflict || (error as? RemoteError) == .unauthorized || (error as? RemoteError) == .incompatible
   if known{remove(intent.requestId)}else if let n=disk.intents.firstIndex(where:{$0.requestId==intent.requestId}){disk.intents[n].phase = .uncertain}
   do{try await persist()}catch{ready=false}
   guard context==c,!Task.isCancelled else{return false};needsRefresh=true
   notice=known ? "The default was not saved. Your selection is kept; refresh and review the current default." : "The save could not be confirmed. Review the current default before making another change."
   return false
  }
 }
 func keepCurrent(context c:WorkspaceDefaultsContext) async throws {
  guard context==c,canKeepCurrent,let id=pending?.requestId else{throw RemoteError.unavailable}
  remove(id);try await persist();reviewed=false;notice=nil
 }
}
