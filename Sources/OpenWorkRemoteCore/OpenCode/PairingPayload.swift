import Foundation

public struct OpenCodePairingPayload: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public let code: String
  public let origins: [URL]
  public var description: String { "OpenCode pairing (\(origins.count) origins)" }
  public var debugDescription: String { description }
  private struct QR: Decodable { let code: String; let urls: [String] }

  public static func parse(_ text: String) throws -> OpenCodePairingPayload {
    guard text.utf8.count <= 16_384 else { throw RemoteError.oversized }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw RemoteError.invalidPairing
    }
    if value.hasPrefix("{") {
      guard let qr = try? JSONDecoder().decode(QR.self, from: Data(value.utf8)),
        valid(code: qr.code), !qr.urls.isEmpty, qr.urls.count <= 16 else { throw RemoteError.invalidPairing }
      var origins: [URL] = []
      for string in qr.urls {
        guard string.utf8.count <= 4_096, let url = URL(string: string) else { throw RemoteError.invalidPairing }
        // The official QR may also advertise LAN HTTP addresses. Never upgrade or contact those.
        if url.scheme == "http" { continue }
        let origin = try OpenCodeOrigin.canonical(url)
        if !origins.contains(origin) { origins.append(origin) }
      }
      guard !origins.isEmpty else { throw RemoteError.invalidPairing }
      return Self(code: qr.code, origins: origins)
    }
    guard var c = URLComponents(string: value), c.scheme == "https",
      c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { throw RemoteError.invalidPairing }
    let prefix = "/auth/connect/"
    guard c.percentEncodedPath.hasPrefix(prefix) else { throw RemoteError.invalidPairing }
    let code = String(c.percentEncodedPath.dropFirst(prefix.count))
    guard valid(code: code) else { throw RemoteError.invalidPairing }
    c.path = ""
    guard let url = c.url else { throw RemoteError.invalidPairing }
    return Self(code: code, origins: [try OpenCodeOrigin.canonical(url)])
  }

  private static func valid(code: String) -> Bool {
    !code.isEmpty && code.utf8.count <= 256 &&
      code.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
  }
}
