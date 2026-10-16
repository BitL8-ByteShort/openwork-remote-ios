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
  /// The server password is used transiently at the explicitly reviewed origin.
  /// Only a fresh native code is returned; normal redemption produces the saved token.
  public func issueUsingServerPassword(origin:URL,password:String)async throws->OpenCodePairingPayload {
    try Task.checkCancellation()
    let reviewed=try OpenCodeOrigin.canonical(origin)
    guard !password.isEmpty,password.utf8.count<=16_384,
      !password.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else{
      throw RemoteError.invalidPairing
    }
    func read(_ path:String,method:String)async throws->Data{
      try Task.checkCancellation()
      guard var parts=URLComponents(url:reviewed,resolvingAgainstBaseURL:false) else{throw RemoteError.invalidPairing}
      parts.path=path
      guard let url=parts.url else{throw RemoteError.invalidPairing}
      var request=URLRequest(url:url,timeoutInterval:20)
      request.httpMethod=method;request.httpShouldHandleCookies=false
      request.setValue("application/json",forHTTPHeaderField:"Accept")
      request.setValue("Basic "+Data(("opencode:"+password).utf8).base64EncodedString(),forHTTPHeaderField:"Authorization")
      let (data,status)=try await transport.data(for:request,maximumBytes:65_536)
      try Task.checkCancellation()
      switch status{
      case 200:break
      case 401:throw RemoteError.unauthorized
      case 403:throw RemoteError.forbidden
      default:throw RemoteError.unavailable
      }
      guard data.count<=65_536 else{throw RemoteError.oversized}
      return data
    }
    let infoData=try await read("/api/info",method:"GET")
    guard let info=try? JSONDecoder().decode(OpenCodeServerInfo.self,from:infoData),
      !info.version.isEmpty,info.version.utf8.count<=128,
      info.urls.count<=32,info.urls.allSatisfy({$0.utf8.count<=4_096}),
      !info.paths.tmp.isEmpty,info.paths.tmp.utf8.count<=8_192,!info.paths.tmp.contains("\0") else{
      throw RemoteError.invalidResponse
    }
    guard OpenCodeCompatibility.evaluate(version:info.version) == .qualified else{throw RemoteError.incompatible}
    let issuedData=try await read("/api/pair",method:"POST")
    struct Issued:Decodable{let code:String;let expires_in:Int}
    guard let issued=try? JSONDecoder().decode(Issued.self,from:issuedData),
      (1...300).contains(issued.expires_in) else{throw RemoteError.invalidResponse}
    // Ignore advertised alternate origins. Never broadcast the password or code.
    let qr=try JSONSerialization.data(withJSONObject:["code":issued.code,"urls":[reviewed.absoluteString]])
    guard let payload=try? OpenCodePairingPayload.parse(String(decoding:qr,as:UTF8.self)) else{
      throw RemoteError.invalidResponse
    }
    return payload
  }
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
