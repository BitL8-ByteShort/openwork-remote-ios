import Foundation

private struct ChangeKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func closedChange(_ decoder: any Decoder, _ keys: [String]) throws {
  let c = try decoder.container(keyedBy:ChangeKey.self)
  guard Set(c.allKeys.map(\.stringValue)).isSubset(of:Set(keys)) else { throw RemoteError.invalidResponse }
}
private func validRevision(_ value: String) -> Bool { value.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil }
private func validChangeID(_ value: String) -> Bool { value.range(of:"^chg_[a-f0-9]{32}$",options:.regularExpression) != nil }
public struct ChangeRef: Codable, Sendable, Equatable, Identifiable {
  public enum Status: String, Codable, Sendable { case added, modified, deleted, renamed, typeChanged }
  public let id: String
  public let pathLabel: String
  public let status: Status
  public let binary: Bool
  public let added: Int?
  public let removed: Int?
  private enum CodingKeys: String, CodingKey, CaseIterable { case id,pathLabel,status,binary,added,removed }
  public init(from decoder: any Decoder) throws {
    try closedChange(decoder,CodingKeys.allCases.map(\.rawValue)); let c=try decoder.container(keyedBy:CodingKeys.self)
    id=try c.decode(String.self,forKey:.id); pathLabel=try c.decode(String.self,forKey:.pathLabel)
    status=try c.decode(Status.self,forKey:.status); binary=try c.decode(Bool.self,forKey:.binary)
    added=try c.decodeIfPresent(Int.self,forKey:.added); removed=try c.decodeIfPresent(Int.self,forKey:.removed)
    try validate()
  }
  public func validate() throws {
    let segments=pathLabel.split(separator:"/",omittingEmptySubsequences:false)
    guard validChangeID(id), !pathLabel.isEmpty, pathLabel.utf8.count <= 500, !pathLabel.contains("\\"),
      segments.allSatisfy({ !$0.isEmpty && ![".","..",".git"].contains(String($0)) }),
      !pathLabel.unicodeScalars.contains(where:{ $0.value < 32 || $0.value == 127 || (0x202a...0x202e).contains($0.value) || (0x2066...0x2069).contains($0.value) }),
      [added,removed].allSatisfy({ count in guard let count else {return true};return (0...20_971_520).contains(count) }),
      binary ? added == nil && removed == nil : added != nil && removed != nil else { throw RemoteError.invalidResponse }
  }
}
public struct ChangeSet: Decodable, Sendable, Equatable {
  public enum UnavailableReason: String, Decodable, Sendable { case nonGit = "non_git", noBaseline = "no_baseline", unsupported }
  public let revision: String
  public let sessionId: String
  public let provenance: String
  public let files: [ChangeRef]
  public let moreOnComputer: Bool
  public let unavailableReason: UnavailableReason?
  private enum CodingKeys: String, CodingKey, CaseIterable { case revision,sessionId,provenance,files,moreOnComputer,unavailableReason }
  public init(from decoder: any Decoder) throws {
    try closedChange(decoder,CodingKeys.allCases.map(\.rawValue)); let c=try decoder.container(keyedBy:CodingKeys.self)
    revision=try c.decode(String.self,forKey:.revision); sessionId=try c.decode(String.self,forKey:.sessionId)
    provenance=try c.decode(String.self,forKey:.provenance); files=try c.decode([ChangeRef].self,forKey:.files)
    moreOnComputer=try c.decode(Bool.self,forKey:.moreOnComputer); unavailableReason=try c.decodeIfPresent(UnavailableReason.self,forKey:.unavailableReason)
    guard validRevision(revision),sessionId.range(of:"^[A-Za-z0-9_-]{1,200}$",options:.regularExpression) != nil,provenance == "workspace",
      files.count <= 100,Set(files.map(\.id)).count == files.count,Set(files.map(\.pathLabel)).count == files.count,
      unavailableReason == nil || files.isEmpty else { throw RemoteError.invalidResponse }
  }
}
public struct FileDiff: Decodable, Sendable, Equatable {
  public let revision: String
  public let changeId: String
  public let binary: Bool
  public let text: String
  public let omitted: Bool
  private enum CodingKeys: String, CodingKey, CaseIterable { case revision,changeId,binary,text,omitted }
  public init(from decoder: any Decoder) throws {
    try closedChange(decoder,CodingKeys.allCases.map(\.rawValue)); let c=try decoder.container(keyedBy:CodingKeys.self)
    revision=try c.decode(String.self,forKey:.revision); changeId=try c.decode(String.self,forKey:.changeId)
    binary=try c.decode(Bool.self,forKey:.binary); text=try c.decode(String.self,forKey:.text); omitted=try c.decode(Bool.self,forKey:.omitted)
    guard validRevision(revision),validChangeID(changeId),text.utf8.count <= 1_048_576,
      text.split(separator:"\n",omittingEmptySubsequences:false).count <= 10_000,!text.utf8.contains(0),
      !binary || text.isEmpty else { throw RemoteError.invalidResponse }
  }
}
extension BridgeClient {
  public func changes(_ wid: String, _ sid: String) async throws -> ChangeSet {
    let result=try await decode(Envelope<ChangeSet>.self,path:(try base(wid,sid))+"/changes").data
    guard result.sessionId == sid else { throw RemoteError.invalidResponse }; return result
  }
  public func diff(_ wid: String, _ sid: String, ref: ChangeRef, revision: String) async throws -> FileDiff {
    try ref.validate(); guard validRevision(revision) else { throw RemoteError.invalidResponse }
    let result=try await decode(Envelope<FileDiff>.self,path:(try base(wid,sid))+"/changes/"+ref.id+"/diff?revision="+revision).data
    guard result.revision == revision,result.changeId == ref.id,result.binary == ref.binary else { throw RemoteError.invalidResponse }
    return result
  }
}
