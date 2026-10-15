import Foundation
import Observation
import OpenWorkRemoteCore

struct NativeProjectKey:Codable,Hashable,Sendable {
  let connectionID:ConnectionID
  let projectID:String
  static func ==(lhs:Self,rhs:Self)->Bool{lhs.connectionID==rhs.connectionID && OpenCodeIdentity.matches(lhs.projectID,rhs.projectID)}
  func hash(into hasher:inout Hasher){hasher.combine(connectionID);hasher.combine(Data(projectID.utf8))}
}
struct LocalChatGroup:Codable,Sendable,Equatable,Identifiable {let id:UUID;var label:String}
struct LocalGroupSnapshot:Codable,Sendable,Equatable {
  var revision:UInt64=0
  var groups:[LocalChatGroup]=[]
  var assignments:[String:UUID]=[:]
  func validate()throws{
    guard groups.count<=100,assignments.count<=10_000,Set(groups.map(\.id)).count==groups.count else{throw RemoteError.oversized}
    for group in groups{guard try SessionGroup.label(group.label)==group.label else{throw RemoteError.invalidResponse}}
    let ids=Set(groups.map(\.id))
    guard assignments.allSatisfy({!$0.key.isEmpty && $0.key.utf8.count<=2_048 && ids.contains($0.value)}) else{throw RemoteError.invalidResponse}
  }
}
struct LocalChatGroupDisk:Codable,Sendable {
  var schemaVersion=1
  var projects:[NativeProjectKey:LocalGroupSnapshot]=[:]
  func validate()throws{
    guard schemaVersion==1,projects.count<=500 else{throw RemoteError.incompatible}
    for (key,value) in projects{
      guard !key.projectID.isEmpty,key.projectID.utf8.count<=2_048 else{throw RemoteError.invalidResponse}
      try value.validate()
    }
  }
}
protocol LocalChatGroupPersistence:Sendable {
  func load()async throws->LocalChatGroupDisk
  func save(_ value:LocalChatGroupDisk,revision:UInt64)async throws
}
actor LocalChatGroupFile:LocalChatGroupPersistence {
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<LocalChatGroupDisk>
  init(directory:URL)throws{
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
      attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
    url=directory.appending(path:"native-local-groups.json");snapshots=RevisionedSnapshotStore(url:url)
  }
  func load()async throws->LocalChatGroupDisk{
    if FileManager.default.fileExists(atPath:url.path){
      guard let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber,size.intValue<=4_194_304 else{throw RemoteError.oversized}
    }
    let value=try await snapshots.load() ?? LocalChatGroupDisk();try value.validate();return value
  }
  func save(_ value:LocalChatGroupDisk,revision:UInt64)async throws{
    try value.validate();guard try JSONEncoder().encode(value).count<=4_194_304 else{throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func invalidateAndRemove()async throws{try await snapshots.invalidateAndRemove()}
}
enum LocalGroupAction {case create(String),rename(UUID,String),remove(UUID),assign(sessionID:String,groupID:UUID?),reorder([UUID])}
/// Device-local organization only. This store has no network service or server metadata writer.
@MainActor @Observable final class LocalChatGroupStore {
  private(set) var ready=false
  private(set) var busy=false
  private(set) var scope:NativeProjectKey?
  private var disk=LocalChatGroupDisk()
  @ObservationIgnored private var revision:UInt64=0
  @ObservationIgnored private let persistence:any LocalChatGroupPersistence
  init(persistence:any LocalChatGroupPersistence){self.persistence=persistence}
  var snapshot:LocalGroupSnapshot{scope.flatMap{disk.projects[$0]} ?? LocalGroupSnapshot()}
  func restore()async throws{guard !ready else{return};let value=try await persistence.load();try value.validate();disk=value;ready=true}
  func activate(_ scope:NativeProjectKey?){self.scope=scope}
  func change(_ action:LocalGroupAction,scope:NativeProjectKey,expectedRevision:UInt64)async throws{
    guard ready,!busy,self.scope==scope else{throw RemoteError.unavailable}
    guard snapshot.revision==expectedRevision else{throw RemoteError.conflict}
    var value=snapshot,candidate=disk
    switch action{
    case .create(let name):value.groups.append(LocalChatGroup(id:UUID(),label:try SessionGroup.label(name)))
    case .rename(let id,let name):
      guard let i=value.groups.firstIndex(where:{$0.id==id}) else{throw RemoteError.conflict}
      value.groups[i].label=try SessionGroup.label(name)
    case .remove(let id):
      guard value.groups.contains(where:{$0.id==id}) else{throw RemoteError.conflict}
      value.groups.removeAll{$0.id==id};value.assignments=value.assignments.filter{$0.value != id}
    case .assign(let sessionID,let groupID):
      guard !sessionID.isEmpty,sessionID.utf8.count<=2_048,groupID.map({id in value.groups.contains{$0.id==id}}) ?? true else{throw RemoteError.invalidResponse}
      if let groupID{value.assignments[sessionID]=groupID}else{value.assignments.removeValue(forKey:sessionID)}
    case .reorder(let ids):
      guard ids.count==value.groups.count,Set(ids)==Set(value.groups.map(\.id)) else{throw RemoteError.invalidResponse}
      let byID=Dictionary(uniqueKeysWithValues:value.groups.map{($0.id,$0)});value.groups=ids.compactMap{byID[$0]}
    }
    guard value != snapshot else{return}
    guard value.revision<UInt64.max else{throw RemoteError.oversized};value.revision+=1
    candidate.projects[scope]=value;try candidate.validate()
    busy=true;defer{busy=false};revision &+= 1
    try await persistence.save(candidate,revision:revision)
    disk=candidate
  }
}
