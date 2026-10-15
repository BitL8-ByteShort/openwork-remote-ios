import Foundation

public struct PairingToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public let token: String
  public let origin: URL
  public var description: String { "OpenCode pairing credential (redacted)" }
  public var debugDescription: String { description }
}
public struct OpenCodePairingClient: Sendable {
  let transport: any HTTPTransport
  public init(transport: any HTTPTransport = SessionTransport(profile:.openCode)) { self.transport = transport }
  public func redeem(_ payload: OpenCodePairingPayload, origin: URL) async throws -> PairingToken {
    try Task.checkCancellation()
    let reviewed = try OpenCodeOrigin.canonical(origin)
    guard payload.origins.contains(reviewed),
      var c = URLComponents(url: reviewed, resolvingAgainstBaseURL: false) else { throw RemoteError.invalidPairing }
    c.path = "/auth/connect/" + payload.code
    guard let url = c.url else { throw RemoteError.invalidPairing }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"; request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    // One request only. A lost response may have consumed this single-use code.
    let (data, status) = try await transport.data(for: request)
    try Task.checkCancellation()
    if status == 401 { throw RemoteError.unauthorized }
    guard status == 200 else { throw RemoteError.unavailable }
    guard data.count <= 65_536 else { throw RemoteError.oversized }
    struct Response: Decodable { let token: String }
    guard let body = try? JSONDecoder().decode(Response.self, from: data),
      !body.token.isEmpty, body.token.utf8.count <= 16_384,
      !body.token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw RemoteError.invalidResponse
    }
    return PairingToken(token: body.token, origin: reviewed)
  }
}
