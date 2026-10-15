import Foundation
import Observation
import OpenWorkRemoteCore

/// Display preferences only. Native pairing still grants server-wide access.
struct NativeProjectVisibility:Codable,Sendable,Equatable {
  var showNewProjects=true
  private var known=Set<String>()
  private var hidden=Set<String>()
  mutating func observe(_ ids:Set<String>) {
    if !showNewProjects {hidden.formUnion(ids.subtracting(known))}
    known.formUnion(ids)
  }
  mutating func setShown(_ id:String,shown:Bool) {
    known.insert(id)
    if shown {hidden.remove(id)} else {hidden.insert(id)}
  }
  func shows(_ id:String)->Bool {!hidden.contains(id) && (known.contains(id) || showNewProjects)}
  func validate() throws {
    guard known.count<=10_000,hidden.count<=10_000,
      known.union(hidden).allSatisfy({!$0.isEmpty && $0.utf8.count<=2_048}) else {throw RemoteError.invalidResponse}
  }
}
struct NativeVisibilitySnapshot:Codable,Sendable,Equatable {
  var schemaVersion=1
  var connections:[String:NativeProjectVisibility]=[:]
  func validate() throws {
    guard schemaVersion==1,connections.keys.allSatisfy({UUID(uuidString:$0) != nil}) else {throw RemoteError.incompatible}
    for policy in connections.values {try policy.validate()}
  }
}
protocol NativeVisibilityPersistence:Sendable {
  func load() async throws -> NativeVisibilitySnapshot
  func save(_ value:NativeVisibilitySnapshot,revision:UInt64) async throws
}
actor NativeVisibilityFile:NativeVisibilityPersistence {
  private let url:URL
  private let snapshots:RevisionedSnapshotStore<NativeVisibilitySnapshot>
  init(directory:URL) throws {
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
      attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
    url=directory.appending(path:"project-visibility.json")
    snapshots=RevisionedSnapshotStore(url:url)
  }
  func load() async throws -> NativeVisibilitySnapshot {
    if FileManager.default.fileExists(atPath:url.path) {
      let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
      guard let size=attributes[.size] as? NSNumber,size.intValue<=4_194_304 else {throw RemoteError.oversized}
    }
    let result=try await snapshots.load() ?? NativeVisibilitySnapshot()
    try result.validate();return result
  }
  func save(_ value:NativeVisibilitySnapshot,revision:UInt64) async throws {
    try value.validate()
    guard try JSONEncoder().encode(value).count<=4_194_304 else {throw RemoteError.oversized}
    try await snapshots.save(value,revision:revision)
  }
  func retireWriter()async{await snapshots.retire()}
  func invalidateAndRemove()async throws{try await snapshots.invalidateAndRemove()}
}
@MainActor @Observable final class NativeProjectVisibilityStore {
  private(set) var ready=false
  private(set) var busy=false
  private(set) var lastError:String?
  private var values=NativeVisibilitySnapshot()
  private var connection:String?
  @ObservationIgnored private let persistence:any NativeVisibilityPersistence
  @ObservationIgnored private var revision:UInt64=0
  var policy:NativeProjectVisibility {connection.flatMap{values.connections[$0]} ?? NativeProjectVisibility()}
  init(persistence:any NativeVisibilityPersistence) {self.persistence=persistence}
  func restore() async throws {
    guard !ready else{return}
    do {let result=try await persistence.load();try result.validate();values=result;ready=true;lastError=nil}
    catch {lastError="Your saved project list preferences couldn’t be opened.";throw error}
  }
  func activate(_ id:ConnectionID) {connection=id.rawValue.uuidString.lowercased()}
  func observe(_ ids:Set<String>) async throws {try await update{$0.observe(ids)}}
  func setShown(_ id:String,shown:Bool) async throws {try await update{$0.setShown(id,shown:shown)}}
  func setShowNewProjects(_ value:Bool) async throws {try await update{$0.showNewProjects=value}}
  private func update(_ change:(inout NativeProjectVisibility)->Void) async throws {
    guard ready,!busy,let connection else{throw RemoteError.unavailable}
    var candidate=values,policy=self.policy
    change(&policy);candidate.connections[connection]=policy
    try candidate.validate()
    guard candidate != values else{return}
    busy=true;defer{busy=false}
    revision &+= 1
    do {try await persistence.save(candidate,revision:revision);values=candidate;lastError=nil}
    catch {lastError="Your project list preferences couldn’t be saved.";throw error}
  }
}
