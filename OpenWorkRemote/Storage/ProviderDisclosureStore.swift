import Foundation
import Observation
import OpenWorkRemoteCore

struct ProviderSharingConsent:Codable,Sendable{
  let destination:OpenCodeSharingDestination
  let classes:Set<OpenCodeSharedData>
  let policyVersion:String
  let approvedAt:Date
}
struct ProviderDisclosureDisk:Codable,Sendable{
  var schemaVersion=1
  var consents:[ProviderSharingConsent]=[]
  func validate()throws{
    guard schemaVersion==1,consents.count<=1_000 else{throw RemoteError.incompatible}
    for record in consents{
      try record.destination.validate()
      guard !record.classes.isEmpty,!record.policyVersion.isEmpty,record.policyVersion.utf8.count<=128,
        record.approvedAt.timeIntervalSince1970.isFinite else{throw RemoteError.invalidResponse}
    }
  }
}
protocol ProviderDisclosurePersistence:Sendable{
  func load()async throws->ProviderDisclosureDisk
  func save(_ value:ProviderDisclosureDisk,revision:UInt64)async throws
}
actor ProviderDisclosureFile:ProviderDisclosurePersistence{
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<ProviderDisclosureDisk>
  init(directory:URL){url=directory.appending(path:"native-sharing-consent.json");snapshots=RevisionedSnapshotStore(url:url)}
  func load()async throws->ProviderDisclosureDisk{
    if FileManager.default.fileExists(atPath:url.path){
      guard let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber,size.intValue<=2_097_152 else{throw RemoteError.oversized}
    }
    let disk=try await snapshots.load() ?? ProviderDisclosureDisk();try disk.validate();return disk
  }
  func save(_ value:ProviderDisclosureDisk,revision:UInt64)async throws{
    try value.validate();guard try JSONEncoder().encode(value).count<=2_097_152 else{throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func retireWriter()async{await snapshots.retire()}
  func invalidateAndRemove()async throws{try await snapshots.invalidateAndRemove()}
}
struct ProviderDisclosureReview:Identifiable,Sendable{
  let id=UUID()
  let target:OpenCodeTarget
  let destination:OpenCodeSharingDestination
  let classes:Set<OpenCodeSharedData>
  let policyVersion:String
  let operation:OpenCodeSharingOperation
}
struct NativeSharingReviewRequired:Error,Sendable{}
/// Review is local and deliberate. It never starts or retries the user's operation.
@MainActor @Observable final class ProviderDisclosureStore{
  static let policyVersion="2026-10-16.1"
  private(set) var ready=false
  private(set) var review:ProviderDisclosureReview?
  private(set) var saving=false
  private(set) var storageIssue=false
  var notice:String?
  private var disk=ProviderDisclosureDisk()
  @ObservationIgnored private let persistence:any ProviderDisclosurePersistence
  @ObservationIgnored private var target:OpenCodeTarget?
  @ObservationIgnored private var generation=UUID()
  @ObservationIgnored private var revision:UInt64=0
  @ObservationIgnored private var clearing=false
  init(persistence:any ProviderDisclosurePersistence){self.persistence=persistence}
  func restore()async throws{guard !ready else{return};let value=try await persistence.load();try value.validate();disk=value;ready=true}
  func activate(_ target:OpenCodeTarget?){generation=UUID();self.target=target;review=nil;notice=nil;saving=false}
  func requiresReview(destination:OpenCodeSharingDestination,classes:Set<OpenCodeSharedData>,policyVersion:String=ProviderDisclosureStore.policyVersion)->Bool{
    !disk.consents.contains{$0.destination.id==destination.id && $0.policyVersion==policyVersion && $0.classes.isSuperset(of:classes)}
  }
  func authorize(target:OpenCodeTarget,reader:any OpenCodeSharingReading,classes:Set<OpenCodeSharedData>,operation:OpenCodeSharingOperation = .message)async->Bool{
    await authorization(target:target,reader:reader,classes:classes,operation:operation) == .approved
  }
  func requireAuthorization(target:OpenCodeTarget,reader:any OpenCodeSharingReading,classes:Set<OpenCodeSharedData>,operation:OpenCodeSharingOperation)async throws{
    switch await authorization(target:target,reader:reader,classes:classes,operation:operation){
    case .approved:return
    case .reviewRequired:
      guard operation == .attachment else{throw RemoteError.forbidden}
      throw NativeSharingReviewRequired()
    case .unavailable:throw RemoteError.forbidden
    }
  }
  private enum Authorization{case approved,reviewRequired,unavailable}
  private func authorization(target:OpenCodeTarget,reader:any OpenCodeSharingReading,classes:Set<OpenCodeSharedData>,operation:OpenCodeSharingOperation)async->Authorization{
    if storageIssue{notice="Sharing permissions could not be cleared. Unlock this device and clear them again in Data Controls.";return .unavailable}
    guard ready,!saving,!clearing,self.target==target,!classes.isEmpty,!Task.isCancelled else{return .unavailable}
    let current=generation
    do{
      let destination=try await reader.sharingDestination(target:target)
      try destination.validate()
      guard generation==current,self.target==target,!Task.isCancelled,destination.connectionID==target.connectionID else{return .unavailable}
      guard requiresReview(destination:destination,classes:classes) else{return .approved}
      if review?.destination.id != destination.id || review?.classes != classes || review?.target != target || review?.operation != operation{
        review=ProviderDisclosureReview(target:target,destination:destination,classes:classes,policyVersion:Self.policyVersion,operation:operation)
      }
      notice="Review where your data may be shared before continuing."
      return .reviewRequired
    }catch{if generation==current{notice="The provider context could not be checked. Keep your draft and reconnect before sharing."}}
    return .unavailable
  }
  func approve(_ request:ProviderDisclosureReview,using reader:any OpenCodeSharingReading,acknowledgesUnknownDestination:Bool)async->Bool{
    guard ready,!saving,!clearing,!storageIssue,review?.id==request.id,target==request.target,
      request.policyVersion==Self.policyVersion,
      request.destination.finalEndpointVerified || acknowledgesUnknownDestination else{return false}
    let current=generation;saving=true;defer{if generation==current{saving=false}}
    do{
      let fresh=try await reader.sharingDestination(target:request.target)
      try fresh.validate()
      guard generation==current,review?.id==request.id,target==request.target,!Task.isCancelled else{return false}
      guard fresh.id==request.destination.id else{
        review=ProviderDisclosureReview(target:request.target,destination:fresh,classes:request.classes,policyVersion:Self.policyVersion,operation:request.operation)
        notice="OpenCode’s reported provider configuration changed. Review the updated destination.";return false
      }
      var candidate=disk
      candidate.consents.removeAll{$0.destination.id==fresh.id && $0.policyVersion==request.policyVersion && request.classes.isSuperset(of:$0.classes)}
      candidate.consents.append(ProviderSharingConsent(destination:fresh,classes:request.classes,policyVersion:request.policyVersion,approvedAt:Date()))
      try candidate.validate();revision &+= 1;try await persistence.save(candidate,revision:revision)
      guard generation==current,review?.id==request.id,target==request.target else{return false}
      disk=candidate;review=nil;notice=nil;return true
    }catch{if generation==current{notice="Sharing permission could not be saved. Unlock this device and try again."};return false}
  }
  func cancelReview(){generation=UUID();review=nil;saving=false;notice=nil}
  func clearConsents()async throws{
    guard ready,!clearing else{throw RemoteError.unavailable}
    clearing=true;defer{clearing=false}
    cancelReview();disk=ProviderDisclosureDisk();storageIssue=true;revision &+= 1
    do{try await persistence.save(disk,revision:revision);storageIssue=false}
    catch{notice="Sharing permissions could not be cleared. Unlock this device and try again.";throw error}
  }
}
