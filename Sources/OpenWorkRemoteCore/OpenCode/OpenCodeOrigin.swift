import Foundation

enum OpenCodeOrigin {
  static func canonical(_ url: URL) throws -> URL {
    _ = try PairingValidation.origin(url.absoluteString)
    guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
      c.percentEncodedPath.isEmpty || c.percentEncodedPath == "/" else {
      throw RemoteError.invalidPairing
    }
    c.path = ""; c.host = c.host?.lowercased()
    if c.port == 443 { c.port = nil }
    guard let result = c.url else { throw RemoteError.invalidPairing }
    return result
  }
}
