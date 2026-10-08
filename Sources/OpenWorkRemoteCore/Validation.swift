import Foundation

public enum RemoteError: Error, Sendable, Equatable {
  case invalidPairing, oversized, invalidResponse, unauthorized, forbidden, incompatible,
    unavailable, cancelled, outcomeUnknown, notFound, conflict
}
public enum PairingValidation {
  public static func origin(_ string: String) throws -> URL {
    guard let c = URLComponents(string: string), c.scheme == "https", let host = c.host,
      !host.isEmpty, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
      c.path.isEmpty || c.path == "/", c.port == nil || (1...65535).contains(c.port!),
      let url = c.url
    else { throw RemoteError.invalidPairing }
    return url
  }
}
public struct SSEFrame: Equatable, Sendable {
  public let event: String
  public let id: String?
  public let data: String
  public init(event: String, id: String?, data: String) {
    self.event = event
    self.id = id
    self.data = data
  }
}
public struct SSEParser: Sendable {
  private var buffer = Data()
  private let limit: Int
  public init(limit: Int = 1_048_576) { self.limit = limit }
  public mutating func push(_ bytes: Data) throws -> [SSEFrame] {
    buffer.append(bytes)
    var result: [SSEFrame] = []
    while true {
      let lf = buffer.range(of: Data([10, 10]))
      let crlf = buffer.range(of: Data([13, 10, 13, 10]))
      let range: [Range<Data.Index>] = [lf, crlf].compactMap { $0 }
      guard let end = range.min(by: { $0.lowerBound < $1.lowerBound }) else { break }
      let frame = buffer.subdata(in: buffer.startIndex..<end.lowerBound)
      buffer.removeSubrange(buffer.startIndex..<end.upperBound)
      guard frame.count <= limit else { throw RemoteError.oversized }
      guard let text = String(data: frame, encoding: .utf8) else {
        throw RemoteError.invalidResponse
      }
      var event = "message"
      var id: String?
      var data: [String] = []
      for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(
        separator: "\n", omittingEmptySubsequences: false)
      {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.first == " " { value.removeFirst() }
        switch field {
        case "event": event = value
        case "id": if !value.contains("\0") { id = value }
        case "data": data.append(value)
        default: break
        }
      }
      if !data.isEmpty {
        result.append(SSEFrame(event: event, id: id, data: data.joined(separator: "\n")))
      }
    }
    guard buffer.count <= limit else { throw RemoteError.oversized }
    return result
  }
}
