import Foundation
import Observation
import OpenWorkRemoteCore

struct NativeLastSelection:Codable,Sendable{
  let projectID:String
  let chat:OpenCodeTarget?
}
struct NativeSelectionDisk:Codable,Sendable{
  var schemaVersion=1
  var connections:[ConnectionID:NativeLastSelection]=[:]
  func validate()throws{
    guard schemaVersion==1,connections.count<=100 else{throw RemoteError.incompatible}
    for (id,value) in connections{
      guard !value.projectID.isEmpty,value.projectID.utf8.count<=2_048 else{throw RemoteError.invalidResponse}
      if let target=value.chat{
        guard target.connectionID==id,OpenCodeIdentity.matches(target.projectID,value.projectID),
          target.directory.hasPrefix("/"),target.directory.utf8.count<=8_192,!target.directory.contains("\0"),
          target.sessionID.hasPrefix("ses"),target.sessionID.utf8.count<=2_048 else{throw RemoteError.invalidResponse}
      }
    }
  }
}
actor NativeSelectionFile{
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<NativeSelectionDisk>
  init(directory:URL){url=directory.appending(path:"native-selection.json");snapshots=RevisionedSnapshotStore(url:url)}
  func load()async throws->NativeSelectionDisk{
    if FileManager.default.fileExists(atPath:url.path){
      guard let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber,size.intValue<=1_048_576 else{throw RemoteError.oversized}
    }
    let value=try await snapshots.load() ?? NativeSelectionDisk();try value.validate();return value
  }
  func save(_ value:NativeSelectionDisk,revision:UInt64)async throws{
    try value.validate();guard try JSONEncoder().encode(value).count<=1_048_576 else{throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func retireWriter()async{await snapshots.retire()}
  func invalidateAndRemove()async throws{try await snapshots.invalidateAndRemove()}
}
@MainActor @Observable final class NativeSelectionStore{
  private(set) var ready=false
  private var disk=NativeSelectionDisk()
  @ObservationIgnored private var revision:UInt64=0
  @ObservationIgnored private let file:NativeSelectionFile
  init(file:NativeSelectionFile){self.file=file}
  func restore()async throws{guard !ready else{return};disk=try await file.load();ready=true}
  func value(for id:ConnectionID)->NativeLastSelection?{disk.connections[id]}
  func remember(connection:ConnectionID,projectID:String,chat:OpenCodeTarget?)async throws{
    guard ready else{throw RemoteError.unavailable}
    var value=disk;value.connections[connection]=NativeLastSelection(projectID:projectID,chat:chat)
    try value.validate();disk=value;revision &+= 1
    try await file.save(value,revision:revision)
  }
}
