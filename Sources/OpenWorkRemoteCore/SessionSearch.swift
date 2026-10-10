import Foundation

private struct SearchKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func validSearchCursor(_ value: String) -> Bool {
  value.range(
    of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    options: .regularExpression) != nil
}
public struct SessionSearchPage: Decodable, Sendable {
  public let data: [ChatSession], cursor: String?, scanned: Int, complete: Bool
  private enum CodingKeys: String, CodingKey, CaseIterable { case data, cursor, scanned, complete }
  public init(from decoder: any Decoder) throws {
    let keys = try decoder.container(keyedBy: SearchKey.self)
    guard Set(keys.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
      throw RemoteError.invalidResponse
    }
    let c = try decoder.container(keyedBy: CodingKeys.self)
    data = try c.decode([ChatSession].self, forKey: .data)
    cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
    scanned = try c.decode(Int.self, forKey: .scanned)
    complete = try c.decode(Bool.self, forKey: .complete)
    guard data.count <= 50, (0...500).contains(scanned), data.count <= scanned,
      complete == (cursor == nil), cursor.map(validSearchCursor) ?? true
    else { throw RemoteError.invalidResponse }
  }
}
extension BridgeClient {
  public func searchSessions(_ wid: String, query: String, cursor: String? = nil) async throws
    -> SessionSearchPage
  {
    guard wid.utf8.count <= 200,
      wid.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
      !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      query.unicodeScalars.count <= 200, query.utf8.count <= 800,
      !query.unicodeScalars.contains(where: {
        $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
      }), cursor.map(validSearchCursor) ?? true
    else { throw RemoteError.invalidResponse }
    let items =
      [URLQueryItem(name: "q", value: query)]
      + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
    var parts = URLComponents()
    parts.queryItems = items
    guard let encoded = parts.percentEncodedQuery else { throw RemoteError.invalidResponse }
    let page = try await decode(
      Envelope<SessionSearchPage>.self,
      path: "/v1/workspaces/" + wid + "/sessions/search?" + encoded
    ).data
    guard page.data.allSatisfy({ $0.workspaceId == wid }) else { throw RemoteError.invalidResponse }
    return page
  }
}
