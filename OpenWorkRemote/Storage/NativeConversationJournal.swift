import Foundation
import Observation
import OpenWorkRemoteCore

enum NativePendingState:String,Codable,Sendable{case prepared,unknown,conflicting}
struct NativePendingPrompt:Codable,Sendable {
  let target:OpenCodeTarget
  let prompt:OpenCodePrompt
  var state:NativePendingState
}
extension OpenCodeTarget {
  var nativeDraftKey:DraftKey {
    DraftKey(hostId:"opencode-v2:"+connectionID.rawValue.uuidString.lowercased(),workspaceId:projectID,sessionId:sessionID)
  }
}
struct NativeConversationDisk:Codable,Sendable {
  var schemaVersion=1
  var drafts:[DraftKey:String]=[:]
  var pending:[DraftKey:NativePendingPrompt]=[:]
  func validate() throws {
    guard schemaVersion==1 else{throw RemoteError.incompatible}
    guard drafts.count<=2_000,pending.count<=100,
      drafts.values.allSatisfy({$0.utf8.count<=32_768}),
      pending.allSatisfy({key,value in
        key==value.target.nativeDraftKey && value.target.directory.hasPrefix("/") &&
          value.target.directory.utf8.count<=8_192 && !value.target.directory.contains("\0") &&
          !value.target.projectID.isEmpty && value.target.projectID.utf8.count<=2_048 &&
          value.target.sessionID.hasPrefix("ses") && value.target.sessionID.utf8.count<=2_048
      }) else{throw RemoteError.invalidResponse}
  }
}
protocol NativeConversationPersistence:Sendable {
  func load() async throws -> NativeConversationDisk
  func save(_ value:NativeConversationDisk,revision:UInt64) async throws
}
actor NativeConversationFile:NativeConversationPersistence {
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<NativeConversationDisk>
  init(directory:URL) throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
      attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
    url=directory.appending(path:"native-conversations.json");snapshots=RevisionedSnapshotStore(url:url)
  }
  func load() async throws -> NativeConversationDisk {
    if FileManager.default.fileExists(atPath:url.path) {
      let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber
      guard let size,size.intValue<=8_388_608 else{throw RemoteError.oversized}
    }
    let result=try await snapshots.load() ?? NativeConversationDisk()
    try result.validate();return result
  }
  func save(_ value:NativeConversationDisk,revision:UInt64) async throws {
    try value.validate()
    guard try JSONEncoder().encode(value).count<=8_388_608 else{throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func invalidateAndRemove() async throws{try await snapshots.invalidateAndRemove()}
}

/// Draft edits are immediate; no network request may precede the durable intent write.
@MainActor @Observable final class NativeConversationJournal {
  private(set) var ready=false
  private(set) var storageIssue=false
  private var disk=NativeConversationDisk()
  @ObservationIgnored private let persistence:any NativeConversationPersistence
  @ObservationIgnored private var revision:UInt64=0
  @ObservationIgnored private var retired=false
  init(persistence:any NativeConversationPersistence){self.persistence=persistence}
  func restore() async throws {
    guard !ready,!retired else{return}
    let result=try await persistence.load();try result.validate()
    guard !retired else{throw RemoteError.unavailable}
    disk=result
    for key in disk.pending.keys where disk.pending[key]?.state == .prepared{disk.pending[key]?.state = .unknown}
    ready=true;storageIssue=false
  }
  func draft(for target:OpenCodeTarget)->String{disk.drafts[target.nativeDraftKey] ?? ""}
  func pending(for target:OpenCodeTarget)->NativePendingPrompt?{disk.pending[target.nativeDraftKey]}
  func saveDraft(_ text:String,for target:OpenCodeTarget) async throws {
    guard ready,!retired,text.utf8.count<=32_768 else{throw RemoteError.unavailable}
    disk.drafts[target.nativeDraftKey]=text
    try await persist()
  }
  func prepare(target:OpenCodeTarget) async throws -> NativePendingPrompt {
    guard ready,!storageIssue,!retired,pending(for:target)==nil else{throw RemoteError.unavailable}
    let item=NativePendingPrompt(target:target,prompt:try OpenCodePrompt(text:draft(for:target)),state:.prepared)
    disk.pending[target.nativeDraftKey]=item
    do{try await persist();return item}
    catch{disk.pending[target.nativeDraftKey]?.state = .unknown;throw error}
  }
  func mark(_ item:NativePendingPrompt,state:NativePendingState) async throws {
    guard pending(for:item.target)?.prompt.id==item.prompt.id else{return}
    disk.pending[item.target.nativeDraftKey]?.state=state
    try await persist()
  }
  func confirm(_ item:NativePendingPrompt) async throws {
    guard pending(for:item.target)?.prompt.id==item.prompt.id else{throw RemoteError.conflict}
    disk.pending.removeValue(forKey:item.target.nativeDraftKey)
    if draft(for:item.target)==item.prompt.text{disk.drafts.removeValue(forKey:item.target.nativeDraftKey)}
    try await persist()
  }
  func reject(_ item:NativePendingPrompt) async throws {
    guard pending(for:item.target)?.prompt.id==item.prompt.id else{return}
    disk.pending.removeValue(forKey:item.target.nativeDraftKey)
    try await persist()
  }
  func retryPersistence() async throws {try await persist()}
  func retire(){retired=true;ready=false}
  private func persist() async throws {
    guard ready,!retired else{throw RemoteError.unavailable}
    revision &+= 1;let current=revision,value=disk
    do{
      try await persistence.save(value,revision:current)
      if current==revision{storageIssue=false}
    }catch{if current==revision{storageIssue=true};throw error}
  }
}
