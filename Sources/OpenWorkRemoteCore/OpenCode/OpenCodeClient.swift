import Foundation

enum OpenCodeResponseBudget:Int {case ordinary=8_388_608,skillCatalog=16_777_216,materializedPrompt=58_720_256}

/// Typed feature methods are the public surface. Raw routing stays inside this module.
public actor OpenCodeClient {
  public let connection: OpenCodeConnection
  private let token: String
  let transport: any HTTPTransport
  nonisolated let lifetime=OpenCodeRequestLifetime()
  private(set) var compatibilityStatus: CompatibilityStatus?
  private var sharingAuthorization:(@Sendable(OpenCodeTarget,Set<OpenCodeSharedData>,OpenCodeSharingOperation)async throws->Void)?

  public init(connection: OpenCodeConnection, token: String,
              transport: any HTTPTransport = SessionTransport(profile: .openCode)) throws {
    guard !token.isEmpty, token.utf8.count <= 16_384,
      !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw RemoteError.invalidPairing
    }
    self.connection = connection; self.token = token; self.transport = OpenCodeScopedTransport(base:transport,lifetime:lifetime)
  }

  public nonisolated func retire(){lifetime.retire()}
  public nonisolated func observeAuthenticationFailure(_ handler:@escaping @Sendable()->Void){lifetime.observeAuthenticationFailure(handler)}
  /// The app installs its deliberate sharing review before exposing native features.
  public func observeSharingAuthorization(_ handler:@escaping @Sendable(OpenCodeTarget,Set<OpenCodeSharedData>,OpenCodeSharingOperation)async throws->Void){sharingAuthorization=handler}
  func requireSharingAuthorization(target:OpenCodeTarget,classes:Set<OpenCodeSharedData>,operation:OpenCodeSharingOperation)async throws{
    try lifetime.requireActive();try Task.checkCancellation()
    try await sharingAuthorization?(target,classes,operation)
    try lifetime.requireActive();try Task.checkCancellation()
  }

  public func info() async throws -> OpenCodeServerInfo {
    let result = try await decode(OpenCodeServerInfo.self, segments: ["api", "info"])
    guard !result.version.isEmpty, result.version.utf8.count <= 128,
      result.urls.count <= 32, result.urls.allSatisfy({ $0.utf8.count <= 4_096 }),
      !result.paths.tmp.isEmpty, result.paths.tmp.utf8.count <= 8_192,
      !result.paths.tmp.contains("\0") else { throw RemoteError.invalidResponse }
    compatibilityStatus = OpenCodeCompatibility.evaluate(version: result.version)
    return result
  }

  func makeRequest(segments: [String], query: [URLQueryItem] = [], method: String = "GET",
                   body: Data? = nil, contentType: String = "application/json") throws -> URLRequest {
    try lifetime.requireActive()
    guard ["GET", "POST", "PATCH", "DELETE"].contains(method), !segments.isEmpty,
      segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 2_048 && !$0.contains("\0") }),
      query.allSatisfy({ $0.name.utf8.count <= 256 && ($0.value?.utf8.count ?? 0) <= 16_384 }),
      var c = URLComponents(url: connection.origin, resolvingAgainstBaseURL: false) else {
      throw RemoteError.invalidResponse
    }
    guard (body?.count ?? 0) <= 56 * 1_048_576 else { throw RemoteError.oversized }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    c.percentEncodedPath = "/" + segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
    c.queryItems = query.isEmpty ? nil : query
    // The native server parses form-style queries, where a literal + means space.
    c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    guard let url = c.url, url.scheme == "https", url.host == connection.origin.host,
      url.port == connection.origin.port, url.user == nil, url.password == nil else { throw RemoteError.invalidResponse }
    var request = URLRequest(url: url)
    request.httpMethod = method; request.httpBody = body; request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Basic " + Data(("opencode:" + token).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
    if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
    return request
  }

  func checkStatus(_ status: Int) throws {
    switch status {
    case 200...299: break
    case 400: throw RemoteError.invalidResponse
    case 401: throw RemoteError.unauthorized
    case 403: throw RemoteError.forbidden
    case 404: throw RemoteError.notFound
    case 409: throw RemoteError.conflict
    case 413: throw RemoteError.oversized
    case 422: throw RemoteError.incompatible
    default: throw RemoteError.unavailable
    }
  }

  func data(segments: [String], query: [URLQueryItem] = [], method: String = "GET",
            body: Data? = nil, contentType: String = "application/json",
            responseBudget: OpenCodeResponseBudget = .ordinary) async throws -> Data {
    try Task.checkCancellation()
    if method != "GET" { try await requireQualifiedWrites() }
    try Task.checkCancellation()
    let request = try makeRequest(segments: segments, query: query, method: method, body: body, contentType: contentType)
    let (bytes, status) = try await transport.data(for: request, maximumBytes: responseBudget.rawValue)
    try Task.checkCancellation()
    guard bytes.count <= responseBudget.rawValue else { throw RemoteError.oversized }
    try checkStatus(status)
    return bytes
  }

  func decode<T: Decodable & Sendable>(_ type: T.Type, segments: [String],
                                       query: [URLQueryItem] = [], responseBudget: OpenCodeResponseBudget = .ordinary) async throws -> T {
    let bytes = try await data(segments: segments, query: query, responseBudget: responseBudget)
    do { return try JSONDecoder().decode(type, from: bytes) }
    catch { throw RemoteError.invalidResponse }
  }

  @discardableResult func requireQualifiedWrites() async throws -> OpenCodeServerInfo {
    // A desktop update can replace the service while the phone stays open.
    let current=try await info()
    guard compatibilityStatus == .qualified else { throw RemoteError.incompatible }
    return current
  }
}
