import Foundation
import Observation
import OpenWorkRemoteCore

struct NativeFormKey:Codable,Hashable,Sendable {
  let target:OpenCodeTarget
  let formID:String
  let fingerprint:Data
}
struct NativeFormRecord:Codable,Sendable {
  var answers:[String:OpenCodeFormValue]=[:]
  /// Presence means status must be checked, including after relaunch.
  var pending:Bool=false
}
struct NativeFormDisk:Codable,Sendable {
  var schemaVersion=1
  var records:[NativeFormKey:NativeFormRecord]=[:]
  func validate()throws{
    guard schemaVersion==1,records.count<=200,records.allSatisfy({key,value in
      key.fingerprint.count==32 && key.formID.hasPrefix("frm_") && key.formID.utf8.count<=2_048 &&
      key.target.sessionID.hasPrefix("ses") && key.target.directory.hasPrefix("/") && value.answers.count<=200
    }),try JSONEncoder().encode(self).count<=8_388_608 else{throw RemoteError.invalidResponse}
  }
}
protocol NativeFormPersistence:Sendable {
  func load() async throws -> NativeFormDisk
  func save(_ value:NativeFormDisk,revision:UInt64) async throws
}
actor NativeFormFile:NativeFormPersistence {
  private let snapshots:RevisionedSnapshotStore<NativeFormDisk>
  private let url:URL
  init(directory:URL)throws{
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
    url=directory.appending(path:"native-forms.json");snapshots=RevisionedSnapshotStore(url:url)
  }
  func load() async throws -> NativeFormDisk{
    if FileManager.default.fileExists(atPath:url.path){let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber;guard let size,size.intValue<=8_388_608 else{throw RemoteError.oversized}}
    let value=try await snapshots.load() ?? NativeFormDisk();try value.validate();return value
  }
  func save(_ value:NativeFormDisk,revision:UInt64) async throws{try value.validate();try await snapshots.save(value,revision:revision)}
  func invalidateAndRemove() async throws{try await snapshots.invalidateAndRemove()}
}
struct NativeFormContext:Hashable,Sendable{let target:OpenCodeTarget;fileprivate let generation:UUID}
enum NativeFormIssue{case unavailable,storage,changed,replyUnconfirmed,authenticationRequired,invalidAnswer}
@MainActor @Observable final class NativeFormStore {
  private(set) var context:NativeFormContext?
  private(set) var pending:[OpenCodeForm]=[]
  private(set) var form:OpenCodeForm?
  private(set) var loading=false
  private(set) var submitting=false
  private(set) var issue:NativeFormIssue?
  private(set) var validation:OpenCodeFormValidation?
  private(set) var ready=false
  private(set) var storageIssue=false
  private var disk=NativeFormDisk()
  @ObservationIgnored private let persistence:any NativeFormPersistence
  @ObservationIgnored private var client:(any OpenCodeFormServing)?
  @ObservationIgnored private var revision:UInt64=0
  @ObservationIgnored private var readID=UUID()
  @ObservationIgnored private var listReadID=UUID()
  @ObservationIgnored private var connectionEpoch=UUID()
  @ObservationIgnored private var boundConnection:ConnectionID?
  @ObservationIgnored private var retired=false
  init(persistence:any NativeFormPersistence){self.persistence=persistence}
  func restore() async throws{
    guard !ready,!retired else{return};let value=try await persistence.load();try value.validate()
    guard !retired else{return};disk=value;ready=true
  }
  @discardableResult func activate(target:OpenCodeTarget,client:any OpenCodeFormServing)->NativeFormContext{
    if boundConnection != target.connectionID{connectionEpoch=UUID();boundConnection=target.connectionID}
    let value=NativeFormContext(target:target,generation:UUID());context=value;self.client=client
    form=nil;pending=[];loading=false;submitting=false;issue=nil;validation=nil;readID=UUID();return value
  }
  func deactivate(){connectionEpoch=UUID();boundConnection=nil;context=nil;client=nil;form=nil;pending=[];loading=false;submitting=false;readID=UUID()}
  func retire(){retired=true;ready=false;deactivate()}
  func close(){form=nil;validation=nil;readID=UUID();loading=false}
  private var key:NativeFormKey?{guard let target=context?.target,let form else{return nil};return NativeFormKey(target:target,formID:form.id,fingerprint:form.definitionFingerprint)}
  var answers:[String:OpenCodeFormValue]{key.flatMap{disk.records[$0]?.answers} ?? [:]}
  var hasUncertainOperation:Bool{
    guard let context,let form else{return false}
    return disk.records.contains{key,value in key.target==context.target && OpenCodeIdentity.matches(key.formID,form.id) && value.pending}
  }
  func refresh(_ context:NativeFormContext) async {
    guard self.context==context,let client else{return}
    let read=UUID();listReadID=read
    do{
      let values=try await client.forms(target:context.target)
      guard self.context==context,listReadID==read,!Task.isCancelled else{return};pending=values
      if let selected=form {
        if let current=values.first(where:{$0.id==selected.id}){
          if current.definitionFingerprint != selected.definitionFingerprint{issue = .changed}
        }else{
          let current=try await client.form(target:context.target,id:selected.id)
          guard self.context==context,listReadID==read,!Task.isCancelled else{return}
          if !current.isPending{form=current;clearPending(target:context.target,formID:current.id);try await flush()}
        }
      }
    }catch{if self.context==context,listReadID==read{issue=error as? RemoteError == .unauthorized ? .authenticationRequired : .unavailable}}
  }
  func receive(_ event:OpenCodeEvent) async {
    guard let context,event.affects(context.target),event.type.hasPrefix("form.") || event.type=="server.connected" || event.type=="location.shutdown" else{return}
    await refresh(context)
  }
  func open(id:String,context:NativeFormContext) async {
    guard self.context==context,let client else{return}
    let read=UUID();readID=read;loading=true;validation=nil
    defer{if self.context==context,readID==read{loading=false}}
    do{
      let actual=try await client.form(target:context.target,id:id)
      guard self.context==context,readID==read,!Task.isCancelled else{return}
      form=actual;issue=nil
      if actual.supported,let key,disk.records[key]==nil{
        var defaults:[String:OpenCodeFormValue]=[:]
        for field in actual.fields{if let value=field.defaultValue{defaults[field.key]=value}}
        disk.records[key]=NativeFormRecord(answers:actual.activeAnswer(defaults))
      }
      if !actual.isPending{clearPending(target:context.target,formID:id);try await flush()}
    }catch{if self.context==context,readID==read{issue=error as? RemoteError == .unauthorized ? .authenticationRequired : .unavailable}}
  }
  func setAnswer(_ value:OpenCodeFormValue?,for field:String){
    guard ready,!retired,!submitting,!hasUncertainOperation,let key,form?.fields.contains(where:{OpenCodeIdentity.matches($0.key,field)})==true else{return}
    disk.records[key,default:NativeFormRecord()].answers[field]=value;validation=nil
    Task{do{try await flush()}catch{issue = .storage}}
  }
  func flush() async throws{
    guard ready,!retired else{throw RemoteError.unavailable};revision &+= 1;let current=revision,value=disk
    do{try await persistence.save(value,revision:current);if current==revision{storageIssue=false}}
    catch{if current==revision{storageIssue=true};throw error}
  }
  func checkStatus(context:NativeFormContext) async{guard let id=form?.id else{return};await open(id:id,context:context);await refresh(context)}
  func submit(context:NativeFormContext) async -> Bool{await settle(context:context,cancel:false)}
  func dismissQuestion(context:NativeFormContext) async -> Bool{await settle(context:context,cancel:true)}
  private func settle(context:NativeFormContext,cancel:Bool) async -> Bool{
    guard self.context==context,let client,let reviewed=form,reviewed.isPending,let key,ready,!storageIssue,!retired,!submitting,!loading,!hasUncertainOperation else{return false}
    let answer=reviewed.activeAnswer(answers)
    if !cancel{do{try reviewed.validate(answer:answer)}catch let value as OpenCodeFormValidation{validation=value;issue = .invalidAnswer;return false}catch{return false}}
    let epoch=connectionEpoch;submitting=true;issue=nil
    defer{if self.context==context{submitting=false}}
    disk.records[key,default:NativeFormRecord()].pending=true
    do{try await flush()}catch{disk.records[key]?.pending=false;issue = .storage;return false}
    guard !retired else{return false}
    if epoch != connectionEpoch || Task.isCancelled{
      disk.records[key]?.pending=false;try? await flush();return false
    }
    do{
      if cancel{_ = try await client.cancelForm(target:context.target,form:reviewed)}
      else{_ = try await client.replyForm(target:context.target,form:reviewed,answer:answer)}
      guard !retired,epoch==connectionEpoch else{return false}
      disk.records[key]?.pending=false;try await flush()
      if self.context==context{await open(id:reviewed.id,context:context);await refresh(context)}
      return true
    }catch{
      guard !retired,epoch==connectionEpoch else{return false}
      if let rejected=error as? OpenCodeFormNotSubmitted{
        disk.records[key]?.pending=false
        do{try await flush()}catch{if self.context==context{issue = .storage};return false}
        if self.context==context{issue=rejected.reason == .unauthorized ? .authenticationRequired : rejected.reason == .conflict ? .changed : .invalidAnswer}
      }else if self.context==context{issue=storageIssue ? .storage : .replyUnconfirmed}
      return false
    }
  }
  private func clearPending(target:OpenCodeTarget,formID:String){
    for key in Array(disk.records.keys) where key.target==target && OpenCodeIdentity.matches(key.formID,formID){disk.records.removeValue(forKey:key)}
  }
}
