import Foundation
import Observation
import OpenWorkRemoteCore

struct LocalChatDefaults:Codable,Sendable,Equatable {
  var model:OpenCodeModelRef?=nil
  var agent:String?=nil
  func validate()throws{
    guard agent.map({!$0.isEmpty && $0.utf8.count<=2_048}) ?? true else{throw RemoteError.invalidResponse}
  }
}
struct LocalChatDefaultsDisk:Codable,Sendable {
  var schemaVersion=1
  var projects:[NativeProjectKey:LocalChatDefaults]=[:]
  func validate()throws{
    guard schemaVersion==1,projects.count<=500 else{throw RemoteError.incompatible}
    for (scope,value) in projects{
      guard !scope.projectID.isEmpty,scope.projectID.utf8.count<=2_048 else{throw RemoteError.invalidResponse}
      try value.validate()
    }
  }
}
protocol LocalChatDefaultsPersistence:Sendable {
  func load()async throws->LocalChatDefaultsDisk
  func save(_ value:LocalChatDefaultsDisk,revision:UInt64)async throws
}
actor LocalChatDefaultsFile:LocalChatDefaultsPersistence {
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<LocalChatDefaultsDisk>
  init(directory:URL)throws{
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
      attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
    url=directory.appending(path:"native-local-defaults.json");snapshots=RevisionedSnapshotStore(url:url)
  }
  func load()async throws->LocalChatDefaultsDisk{
    if FileManager.default.fileExists(atPath:url.path){
      guard let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber,size.intValue<=1_048_576 else{throw RemoteError.oversized}
    }
    let value=try await snapshots.load() ?? LocalChatDefaultsDisk();try value.validate();return value
  }
  func save(_ value:LocalChatDefaultsDisk,revision:UInt64)async throws{
    try value.validate();guard try JSONEncoder().encode(value).count<=1_048_576 else{throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func invalidateAndRemove()async throws{try await snapshots.invalidateAndRemove()}
}
/// These choices only enter a new PocketWork chat's explicit create request.
@MainActor @Observable final class LocalChatDefaultsStore {
  private(set) var ready=false
  private(set) var busy=false
  private(set) var scope:NativeProjectKey?
  private var disk=LocalChatDefaultsDisk()
  @ObservationIgnored private var revision:UInt64=0
  @ObservationIgnored private let persistence:any LocalChatDefaultsPersistence
  init(persistence:any LocalChatDefaultsPersistence){self.persistence=persistence}
  var value:LocalChatDefaults{scope.flatMap{disk.projects[$0]} ?? LocalChatDefaults()}
  func restore()async throws{guard !ready else{return};let value=try await persistence.load();try value.validate();disk=value;ready=true}
  func activate(_ scope:NativeProjectKey?){self.scope=scope}
  func set(_ value:LocalChatDefaults,scope:NativeProjectKey,expected:LocalChatDefaults)async throws{
    guard ready,!busy,self.scope==scope else{throw RemoteError.unavailable}
    guard self.value==expected else{throw RemoteError.conflict}
    try value.validate();var candidate=disk
    if value==LocalChatDefaults(){candidate.projects.removeValue(forKey:scope)}else{candidate.projects[scope]=value}
    try candidate.validate();busy=true;defer{busy=false};revision &+= 1
    try await persistence.save(candidate,revision:revision);disk=candidate
  }
}
