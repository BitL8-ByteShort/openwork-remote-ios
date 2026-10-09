import Foundation

public enum AttachmentValidation {
  public static let chunkBytes = 1_048_576
  public static let fileBytes = 20 * chunkBytes
  public static let promptBytes = 40 * chunkBytes
  public static let stagingBytes = 100 * chunkBytes
  public static func id(_ value: String) throws {
    guard value.range(of: "^att_[a-f0-9]{32}$", options: .regularExpression) != nil else { throw RemoteError.invalidResponse }
  }
  public static func metadata(name: String, mime: String, bytes: Int, sha256: String) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 200,
      name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
      !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, bytes > 0
    else { throw RemoteError.invalidResponse }
    guard bytes <= fileBytes else { throw RemoteError.oversized }
    guard ["image/png", "image/jpeg", "application/pdf"].contains(mime) else { throw RemoteError.incompatible }
  }
  public static func prompt(text: String, ids: [String]) throws {
    guard !ids.isEmpty, ids.count <= 4, Set(ids).count == ids.count else { throw RemoteError.invalidResponse }
    for value in ids { try id(value) }
    guard text.utf8.count <= 32768 else { throw RemoteError.oversized }
  }
}
private struct AttachmentKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func closed(_ decoder: any Decoder, keys: [String]) throws {
  let container = try decoder.container(keyedBy: AttachmentKey.self)
  guard Set(container.allKeys.map(\.stringValue)).isSubset(of: Set(keys)) else { throw RemoteError.invalidResponse }
}
public struct Attachment: Codable, Sendable, Equatable, Identifiable {
  public enum State: String, Codable, Sendable {
    case uploading, committing, ready, sending, attached, outcome_unknown, cancelled, expired
  }
  public let id: String
  public let name: String
  public let mime: String
  public let bytes: Int
  public let sha256: String
  public let receivedBytes: Int
  public let state: State
  private enum CodingKeys: String, CodingKey, CaseIterable { case id, name, mime, bytes, sha256, receivedBytes, state }
  public init(from decoder: any Decoder) throws {
    try closed(decoder, keys: CodingKeys.allCases.map(\.rawValue))
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    mime = try values.decode(String.self, forKey: .mime)
    bytes = try values.decode(Int.self, forKey: .bytes)
    sha256 = try values.decode(String.self, forKey: .sha256)
    receivedBytes = try values.decode(Int.self, forKey: .receivedBytes)
    state = try values.decode(State.self, forKey: .state)
    try validate()
  }
  public func validate() throws {
    try AttachmentValidation.id(id)
    try AttachmentValidation.metadata(name: name, mime: mime, bytes: bytes, sha256: sha256)
    guard (0...bytes).contains(receivedBytes), ![.ready, .sending, .attached].contains(state) || receivedBytes == bytes else {
      throw RemoteError.invalidResponse
    }
  }
}
public struct AttachmentLimits: Codable, Sendable, Equatable {
  public let maxFileBytes: Int
  public let inputMIMEs: [String]
  private enum CodingKeys: String, CodingKey { case maxFileBytes, inputMIMEs }
  public init(from decoder: any Decoder) throws {
    try closed(decoder, keys: ["maxFileBytes", "inputMIMEs"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    maxFileBytes = try values.decode(Int.self, forKey: .maxFileBytes)
    inputMIMEs = try values.decode([String].self, forKey: .inputMIMEs)
    guard (1...AttachmentValidation.fileBytes).contains(maxFileBytes), inputMIMEs.count <= 3,
      Set(inputMIMEs).count == inputMIMEs.count,
      inputMIMEs.allSatisfy({ ["image/png", "image/jpeg", "application/pdf"].contains($0) }) else { throw RemoteError.invalidResponse }
  }
}
public struct AttachmentMutation: Decodable, Sendable {
  public let receipt: MutationReceipt
  public let attachment: Attachment?
  private enum CodingKeys: String, CodingKey { case receipt, attachment }
  public init(from decoder: any Decoder) throws {
    try closed(decoder, keys: ["receipt", "attachment"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    receipt = try values.decode(MutationReceipt.self, forKey: .receipt)
    attachment = try values.decodeIfPresent(Attachment.self, forKey: .attachment)
  }
}
