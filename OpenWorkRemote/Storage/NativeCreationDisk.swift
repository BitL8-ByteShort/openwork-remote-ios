import Foundation
import OpenWorkRemoteCore

struct NativePendingCreation:Codable,Sendable {
  let intent:OpenCodeNewChatIntent
  var state:NativePendingState
}
struct NativeCreationDisk:Codable,Sendable {
  var schemaVersion=1
  var pending:[ConnectionID:NativePendingCreation]=[:]
  func validate()throws{
    guard schemaVersion==1,pending.count<=100 else{throw RemoteError.invalidResponse}
    for (key,value) in pending{
      try value.intent.validate()
      guard key==value.intent.connectionID else{throw RemoteError.invalidResponse}
    }
  }
}
protocol NativeCreationPersistence:Sendable {
  func load() async throws->NativeCreationDisk
  func save(_ value:NativeCreationDisk,revision:UInt64) async throws
}
actor NativeCreationFile:NativeCreationPersistence {
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<NativeCreationDisk>
  init(directory:URL)throws{
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
      attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
    url=directory.appending(path:"native-creations.json");snapshots=RevisionedSnapshotStore(url:url)
  }
  func load()async throws->NativeCreationDisk{
    if FileManager.default.fileExists(atPath:url.path){
      guard let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber,
        size.intValue<=1_048_576 else{throw RemoteError.oversized}
    }
    let value=try await snapshots.load() ?? NativeCreationDisk();try value.validate();return value
  }
  func save(_ value:NativeCreationDisk,revision:UInt64)async throws{
    try value.validate()
    guard try JSONEncoder().encode(value).count<=1_048_576 else{throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func invalidateAndRemove()async throws{try await snapshots.invalidateAndRemove()}
}
