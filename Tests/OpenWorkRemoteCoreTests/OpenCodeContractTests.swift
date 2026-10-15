import Foundation
import Testing
@testable import OpenWorkRemoteCore

actor NativeResponseTransport: HTTPTransport {
  let body: Data
  let status: Int
  private var requests: [URLRequest] = []
  init(_ json: String, status: Int = 200) { body = Data(json.utf8); self.status = status }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request)
    return (body, status)
  }
  func firstRequest() -> URLRequest? { requests.first }
  func requestCount() -> Int { requests.count }
}

@Suite struct OpenCodeContractTests {
  let info = #"{"version":"2.0.29","pid":123,"urls":["https://paired.example"],"paths":{"tmp":"/tmp/opencode"},"capabilities":{"persistentPty":true},"futureField":"ignored"}"#
  func connection(_ origin: String = "https://paired.example:9443") throws -> OpenCodeConnection {
    try OpenCodeConnection(id: ConnectionID(), origin: URL(string: origin)!, displayName: "My computer")
  }
  @Test func nativeInfoUsesBasicAuthenticationOnSavedOrigin() async throws {
    let transport = NativeResponseTransport(info)
    let client = try OpenCodeClient(connection: connection(), token: "paired-token", transport: transport)
    let result = try await client.info()
    #expect(result.version == "2.0.29")
    #expect(result.paths.tmp == "/tmp/opencode")
    let request = try #require(await transport.firstRequest())
    #expect(request.url?.absoluteString == "https://paired.example:9443/api/info")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic b3BlbmNvZGU6cGFpcmVkLXRva2Vu")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
  }
  @Test func invalidConnectionCannotSendARequest() throws {
    for origin in ["http://paired.example", "https://user:password@paired.example", "https://paired.example/path", "https://paired.example/?token=secret", "https://paired.example/#secret"] {
      #expect(throws: RemoteError.invalidPairing) { try connection(origin) }
    }
  }
  @Test func authorizationFailureDiffersFromPermissionFailure() async throws {
    for (status, expected) in [(401, RemoteError.unauthorized), (403, .forbidden), (404, .notFound), (409, .conflict), (413, .oversized)] {
      let client = try OpenCodeClient(connection: connection(), token: "token", transport: NativeResponseTransport(#"{"_tag":"Error","message":"private detail"}"#, status: status))
      await #expect(throws: expected) { try await client.info() }
    }
  }
  @Test func redirectDoesNotBecomeAValidServerResponse() async throws {
    let client = try OpenCodeClient(connection: connection(), token: "token", transport: NativeResponseTransport(info, status: 302))
    await #expect(throws: RemoteError.unavailable) { try await client.info() }
  }
  @Test func malformedOrOversizedJSONIsRejectedBeforeDecoding() async throws {
    for (body, error) in [("{", RemoteError.invalidResponse), (String(repeating: " ", count: 8_388_609), .oversized)] {
      let client = try OpenCodeClient(connection: connection(), token: "token", transport: NativeResponseTransport(body))
      await #expect(throws: error) { try await client.info() }
    }
  }
  @Test func missingRequiredNativeIdentityIsRejected() async throws {
    let client = try OpenCodeClient(connection: connection(), token: "token", transport: NativeResponseTransport(#"{"pid":123,"urls":[],"paths":{"tmp":"/tmp"}}"#))
    await #expect(throws: RemoteError.invalidResponse) { try await client.info() }
  }
  @Test func aCancelledTaskSendsNothing() async throws {
    let transport = NativeResponseTransport(info)
    let client = try OpenCodeClient(connection: connection(), token: "token", transport: transport)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await client.info()
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await transport.requestCount() == 0)
  }
  @Test func versionProfileDoesNotPromiseUnknownNativeSupport() {
    #expect(OpenCodeCompatibility.evaluate(version: "2.0.29") == .qualified)
    #expect(OpenCodeCompatibility.evaluate(version: "2.0.30") == .unverified)
    #expect(OpenCodeCompatibility.evaluate(version: "1.2.0") == .incompatible)
    #expect(OpenCodeCompatibility.evaluate(version: "unknown") == .unverified)
  }
  @Test func nativeConnectionsAreDistinctEvenForEqualSessionIDs() throws {
    let a = try connection(), b = try connection()
    #expect(a.id != b.id)
    let restored = try JSONDecoder().decode(OpenCodeConnection.self, from: JSONEncoder().encode(a))
    #expect(restored == a)
    #expect(restored.backend == .openCodeV2)
  }
  @Test func anUnverifiedServerCannotReceiveAnExperimentalMutation() async throws {
    let transport = NativeResponseTransport(#"{"version":"2.0.30","urls":[],"paths":{"tmp":"/tmp"}}"#)
    let client = try OpenCodeClient(connection: connection(), token: "token", transport: transport)
    await #expect(throws: RemoteError.incompatible) {
      try await client.data(segments: ["api", "session", "ses_owned"], method: "PATCH", body: Data("{}".utf8))
    }
    #expect(await transport.requestCount() == 1)
    #expect(await transport.firstRequest()?.httpMethod == "GET")
  }

}
