import Foundation

private struct ArtifactKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func closedArtifact(_ decoder: any Decoder, _ keys: [String]) throws {
  let values = try decoder.container(keyedBy: ArtifactKey.self)
  guard Set(values.allKeys.map(\.stringValue)).isSubset(of: Set(keys)) else { throw RemoteError.invalidResponse }
}
public struct ArtifactRef: Codable, Sendable, Equatable, Identifiable {
  public enum PreviewKind: String, Codable, Sendable { case text, image, pdf, shareOnly }
  public let id: String
  public let sessionId: String
  public let name: String
  public let mime: String
  public let bytes: Int
  public let revision: String
  public let sha256: String
  public let previewKind: PreviewKind
  private enum CodingKeys: String, CodingKey, CaseIterable { case id, sessionId, name, mime, bytes, revision, sha256, previewKind }
  public init(from decoder: any Decoder) throws {
    try closedArtifact(decoder, CodingKeys.allCases.map(\.rawValue))
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id); sessionId = try c.decode(String.self, forKey: .sessionId)
    name = try c.decode(String.self, forKey: .name); mime = try c.decode(String.self, forKey: .mime)
    bytes = try c.decode(Int.self, forKey: .bytes); revision = try c.decode(String.self, forKey: .revision)
    sha256 = try c.decode(String.self, forKey: .sha256); previewKind = try c.decode(PreviewKind.self, forKey: .previewKind)
    try validate()
  }
  public func validate() throws {
    guard id.range(of: "^art_[a-f0-9]{32}$", options: .regularExpression) != nil,
      sessionId.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 200,
      name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
      !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      (1...20_971_520).contains(bytes),
      revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw RemoteError.invalidResponse }
    let ext = (name as NSString).pathExtension.lowercased()
    let valid: Bool
    switch (mime, previewKind) {
    case ("text/plain", .text): valid = ["txt", "md", "csv", "json", "log"].contains(ext)
    case ("image/png", .image): valid = ext == "png"
    case ("image/jpeg", .image): valid = ["jpg", "jpeg"].contains(ext)
    case ("application/pdf", .pdf): valid = ext == "pdf"
    case ("application/rtf", .shareOnly): valid = ext == "rtf"
    default: valid = false
    }
    guard valid else { throw RemoteError.invalidResponse }
  }
}
public struct ArtifactCatalog: Decodable, Sendable, Equatable {
  public let items: [ArtifactRef]
  public let moreOnComputer: Bool
  private enum CodingKeys: String, CodingKey { case items, moreOnComputer }
  public init(from decoder: any Decoder) throws {
    try closedArtifact(decoder, ["items", "moreOnComputer"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    items = try c.decode([ArtifactRef].self, forKey: .items); moreOnComputer = try c.decode(Bool.self, forKey: .moreOnComputer)
    guard items.count <= 100, Set(items.map(\.id)).count == items.count else { throw RemoteError.invalidResponse }
  }
}
extension BridgeClient {
  public func artifacts(_ wid: String, _ sid: String) async throws -> ArtifactCatalog {
    let result = try await decode(Envelope<ArtifactCatalog>.self, path: (try base(wid, sid)) + "/artifacts").data
    guard result.items.allSatisfy({ $0.sessionId == sid }) else { throw RemoteError.invalidResponse }
    return result
  }
  public func artifactChunk(_ wid: String, _ sid: String, ref: ArtifactRef, offset: Int) async throws -> Data {
    try ref.validate()
    guard ref.sessionId == sid, offset >= 0, offset < ref.bytes, offset.isMultiple(of: 1_048_576) else { throw RemoteError.invalidResponse }
    let end = min(ref.bytes - 1, offset + 1_048_575), count = end - offset + 1
    let response = try await binary((try base(wid, sid)) + "/artifacts/" + ref.id + "/content?revision=" + ref.revision,
      range: "bytes=\(offset)-\(end)", mime: ref.mime, maximumBytes: count)
    guard response.status == 206, response.mime == ref.mime, response.entityTag == "\"\(ref.revision)\"",
      response.contentRange == "bytes \(offset)-\(end)/\(ref.bytes)", response.length == count, response.data.count == count else { throw RemoteError.invalidResponse }
    return response.data
  }
}
