import Foundation

public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, Int)
  func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, Int)
  func binary(for request: URLRequest, maximumBytes: Int) async throws -> BinaryHTTPResponse
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error>
}
extension HTTPTransport {
  public func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, Int) {
    guard (1...56*1_048_576).contains(maximumBytes) else { throw RemoteError.oversized }
    let result = try await data(for: request)
    guard result.0.count <= maximumBytes else { throw RemoteError.oversized }
    return result
  }
  public func binary(for request: URLRequest, maximumBytes: Int) async throws -> BinaryHTTPResponse { throw RemoteError.incompatible }
  public func events(for request: URLRequest) async throws -> AsyncThrowingStream<
    SSEFrame, any Error
  > { throw RemoteError.unavailable }
}
public struct BinaryHTTPResponse: Sendable {
  public let data: Data
  public let status: Int
  public let mime: String?
  public let contentRange: String?
  public let entityTag: String?
  public let length: Int?
  public init(data: Data, status: Int, mime: String?, contentRange: String?, entityTag: String?, length: Int?) {
    self.data = data; self.status = status; self.mime = mime; self.contentRange = contentRange; self.entityTag = entityTag; self.length = length
  }
}
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
public enum HTTPTransportProfile: Sendable { case bridge, openCode }
public actor SessionTransport: HTTPTransport {
  private let session: URLSession
  private let profile: HTTPTransportProfile
  public init(profile: HTTPTransportProfile = .bridge) {
    self.profile = profile
    let c = URLSessionConfiguration.ephemeral
    c.httpShouldSetCookies = false
    if profile == .openCode { c.urlCredentialStorage = nil }
    c.urlCache = nil
    c.requestCachePolicy = .reloadIgnoringLocalCacheData
    c.timeoutIntervalForRequest = 45
    c.timeoutIntervalForResource = 86400
    session = URLSession(configuration: c, delegate: RedirectBlocker(), delegateQueue: nil)
  }
  public func data(for request: URLRequest) async throws -> (Data, Int) {
    try await data(for: request, maximumBytes: 8_388_608)
  }
  public func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, Int) {
    let budget = profile == .openCode ? 56 * 1_048_576 : 8_388_608
    guard (1...budget).contains(maximumBytes) else { throw RemoteError.oversized }
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let http = response as? HTTPURLResponse else { throw RemoteError.invalidResponse }
    guard response.expectedContentLength <= maximumBytes else { throw RemoteError.oversized }
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > maximumBytes { throw RemoteError.oversized }
    }
    return (data, http.statusCode)
  }
  public func binary(for request: URLRequest, maximumBytes: Int) async throws -> BinaryHTTPResponse {
    let budget = profile == .openCode ? 20 * 1_048_576 : 1_048_576
    guard (1...budget).contains(maximumBytes) else { throw RemoteError.oversized }
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let http = response as? HTTPURLResponse else { throw RemoteError.invalidResponse }
    let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init)
    func result(_ data: Data) -> BinaryHTTPResponse {
      BinaryHTTPResponse(data: data, status: http.statusCode, mime: http.mimeType,
        contentRange: http.value(forHTTPHeaderField: "Content-Range"), entityTag: http.value(forHTTPHeaderField: "ETag"), length: length)
    }
    if profile == .bridge {
      guard http.statusCode == 206 else { return result(Data()) }
      guard length == maximumBytes, response.expectedContentLength == maximumBytes else { throw RemoteError.invalidResponse }
    } else {
      guard [200, 206].contains(http.statusCode) else { return result(Data()) }
      if let length { guard length >= 0, length <= maximumBytes else { throw RemoteError.oversized } }
      guard response.expectedContentLength <= maximumBytes else { throw RemoteError.oversized }
    }
    var data = Data(); data.reserveCapacity(min(maximumBytes, length ?? 65_536))
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximumBytes else { throw RemoteError.oversized }
      data.append(byte)
    }
    if profile == .bridge {
      guard data.count == maximumBytes else { throw RemoteError.invalidResponse }
    } else if let length {
      guard data.count == length else { throw RemoteError.invalidResponse }
    }
    return result(data)
  }
  public func events(for request: URLRequest) async throws -> AsyncThrowingStream<
    SSEFrame, any Error
  > {
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw RemoteError.invalidResponse }
    if http.statusCode == 401 { throw RemoteError.unauthorized }
    if http.statusCode == 403 { throw RemoteError.forbidden }
    if http.statusCode == 422 { throw RemoteError.incompatible }
    guard http.statusCode == 200, response.mimeType == "text/event-stream" else {
      throw RemoteError.unavailable
    }
    let frameLimit = profile == .openCode ? 262_144 : 16_384
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
      let task = Task {
        defer { bytes.task.cancel() }
        var parser = SSEParser(limit: frameLimit)
        var chunk = Data()
        do {
          for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if byte == 10 || chunk.count >= 4096 {
              for event in try parser.push(chunk) {
                guard
                  event.data.utf8.count + (event.id?.utf8.count ?? 0)
                    + event.event.utf8.count <= frameLimit
                else { throw RemoteError.oversized }
                if case .dropped = continuation.yield(event) { throw RemoteError.oversized }
              }
              chunk.removeAll(keepingCapacity: true)
            }
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
