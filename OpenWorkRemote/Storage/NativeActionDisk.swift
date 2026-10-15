import Foundation
import OpenWorkRemoteCore

enum NativeChatAction:Codable,Sendable,Equatable {
  case fork(beforeMessageID:String?)
  case delete(OpenCodeSessionTree)
}
struct NativePendingAction:Codable,Sendable,Identifiable {
  let id:UUID
  let target:OpenCodeTarget
  let action:NativeChatAction
  var state:NativePendingState
}
struct NativeActionDisk:Codable,Sendable {
  var schemaVersion=1
  var pending:[OpenCodeTarget:NativePendingAction]=[:]
  func validate()throws{
    guard schemaVersion==1,pending.count<=100 else{throw RemoteError.invalidResponse}
    for (key,value) in pending{
      guard key==value.target,!key.projectID.isEmpty,key.projectID.utf8.count<=2_048,
        key.sessionID.hasPrefix("ses"),key.sessionID.utf8.count<=2_048,
        key.directory.hasPrefix("/"),key.directory.utf8.count<=8_192,!key.directory.contains("\0") else{throw RemoteError.invalidResponse}
      switch value.action{
      case .fork(let before):guard before.map({!$0.isEmpty && $0.utf8.count<=2_048}) ?? true else{throw RemoteError.invalidResponse}
      case .delete(let tree):try tree.validate();guard tree.target==key else{throw RemoteError.conflict}
      }
    }
  }
}
protocol NativeActionPersistence:Sendable {
  func load()async throws->NativeActionDisk
  func save(_ value:NativeActionDisk,revision:UInt64)async throws
}
actor NativeActionFile:NativeActionPersistence {
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<NativeActionDisk>
  init(directory:URL)throws{
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
      attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
    url=directory.appending(path:"native-chat-actions.json");snapshots=RevisionedSnapshotStore(url:url)
  }
  func load()async throws->NativeActionDisk{
    if FileManager.default.fileExists(atPath:url.path){
      guard let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber,
        size.intValue<=4_194_304 else{throw RemoteError.oversized}
    }
    let value=try await snapshots.load() ?? NativeActionDisk();try value.validate();return value
  }
  func save(_ value:NativeActionDisk,revision:UInt64)async throws{
    try value.validate();guard try JSONEncoder().encode(value).count<=4_194_304 else{throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func invalidateAndRemove()async throws{try await snapshots.invalidateAndRemove()}
}
