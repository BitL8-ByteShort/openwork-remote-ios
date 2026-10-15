import Foundation
import Network
import Testing
@testable import OpenWorkRemoteCore

/// A loopback-only real HTTP fixture exercises URLSession's byte and SSE handling.
private final class NativeHTTPFixture: @unchecked Sendable {
  let listener: NWListener
  let payload: Data
  init(body: Data, status: Int = 200, contentType: String = "application/octet-stream") throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
    let reason = status == 206 ? "Partial Content" : "OK"
    payload = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
  }
  func start() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { [self] state in
        switch state {
        case .ready:
          listener.stateUpdateHandler = nil
          continuation.resume(returning: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/fixture")!)
        case .failed(let error):
          listener.stateUpdateHandler = nil
          continuation.resume(throwing: error)
        default: break
        }
      }
      listener.newConnectionHandler = { [self] connection in
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { _, _, _, _ in
          connection.send(content: self.payload, completion: .contentProcessed { _ in connection.cancel() })
        }
      }
      listener.start(queue: .global())
    }
  }
  func stop() { listener.newConnectionHandler = nil; listener.stateUpdateHandler = nil; listener.cancel() }
}

@Suite struct OpenCodeTransportTests {
  @Test func nativeFileReadsAcceptBounded200AndPartial206() async throws {
    for status in [200, 206] {
      let server = try NativeHTTPFixture(body: Data("native file".utf8), status: status)
      defer { server.stop() }
      let url = try await server.start()
      let response = try await SessionTransport(profile: .openCode).binary(for: URLRequest(url: url), maximumBytes: 1024)
      #expect(response.status == status)
      #expect(response.data == Data("native file".utf8))
    }
  }
  @Test func aNativeDownloadNeverExceedsTheRequestedByteBudget() async throws {
    let server = try NativeHTTPFixture(body: Data(repeating: 65, count: 1025))
    defer { server.stop() }
    let url = try await server.start()
    await #expect(throws: RemoteError.oversized) {
      try await SessionTransport(profile: .openCode).binary(for: URLRequest(url: url), maximumBytes: 1024)
    }
  }
  @Test func nativeEventsCanExceedTheOldBridgeFrameLimit() async throws {
    let data = "data: " + String(repeating: "a", count: 20_000) + "\n\n"
    let server = try NativeHTTPFixture(body: Data(data.utf8), contentType: "text/event-stream")
    defer { server.stop() }
    let url = try await server.start()
    let stream = try await SessionTransport(profile: .openCode).events(for: URLRequest(url: url))
    var frames: [SSEFrame] = []
    for try await frame in stream { frames.append(frame) }
    #expect(frames.count == 1)
    #expect(frames.first?.data.utf8.count == 20_000)
  }
  @Test func nativeEventsRejectFramesBeyondTheirBoundRatherThanTruncating() async throws {
    let data = "data: " + String(repeating: "a", count: 262_145) + "\n\n"
    let server = try NativeHTTPFixture(body: Data(data.utf8), contentType: "text/event-stream")
    defer { server.stop() }
    let url = try await server.start()
    await #expect(throws: RemoteError.oversized) {
      let stream = try await SessionTransport(profile: .openCode).events(for: URLRequest(url: url))
      for try await _ in stream {}
    }
  }
  @Test func nativeSegmentsAndLocationValuesCannotRedirectCredentials() async throws {
    let client = try OpenCodeClient(connection: OpenCodeConnection(origin: URL(string:"https://paired.example:9443")!, displayName:"Computer"), token:"token", transport:NativeResponseTransport("{}"))
    let request = try await client.makeRequest(segments:["api","session","ses_a/b?x#f"], query:[URLQueryItem(name:"location[directory]",value:"/home/user/A & B")])
    #expect(request.url?.host == "paired.example")
    #expect(request.url?.port == 9443)
    #expect(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.percentEncodedPath == "/api/session/ses_a%2Fb%3Fx%23f")
    #expect(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems == [URLQueryItem(name:"location[directory]",value:"/home/user/A & B")])
  }
}
