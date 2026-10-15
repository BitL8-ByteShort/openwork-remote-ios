import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodePairingTests {
  let code = "synthetic_pairing-code_123"
  @Test func nativeQRPreservesDistinctHTTPSOriginsForExplicitChoice() throws {
    let payload = try OpenCodePairingPayload.parse(#"{"code":"synthetic_pairing-code_123","urls":["https://one.example/","http://192.0.2.1:4096","https://two.example:9443","https://one.example"]}"#)
    #expect(payload.code == code)
    #expect(payload.origins.map(\.absoluteString) == ["https://one.example", "https://two.example:9443"])
  }
  @Test func copiedNativeLinkIsParsedWithoutOpeningIt() throws {
    let payload = try OpenCodePairingPayload.parse(" https://one.example/auth/connect/\(code)\n")
    #expect(payload.code == code)
    #expect(payload.origins.map(\.absoluteString) == ["https://one.example"])
  }
  @Test func malformedOrCredentialBearingLinksAreRejected() throws {
    for value in ["12345678", "http://one.example/auth/connect/\(code)", "https://user:password@one.example/auth/connect/\(code)", "https://one.example/auth/connect/\(code)?next=other", "https://one.example/auth/connect/\(code)#fragment", "https://one.example/auth/connect/encoded%2Fcode", "https://one.example/auth/connect/", "https://one.example/other/\(code)"] {
      #expect(throws: RemoteError.invalidPairing) { try OpenCodePairingPayload.parse(value) }
    }
    #expect(throws: RemoteError.oversized) { try OpenCodePairingPayload.parse(String(repeating:"x",count:16_385)) }
  }
  @Test func aQRWithNoSafeOriginOrInvalidCodeCannotBeRedeemed() throws {
    for value in [#"{"code":"synthetic","urls":["http://192.0.2.1"]}"#, #"{"code":"bad/code","urls":["https://one.example"]}"#, #"{"code":"synthetic","urls":[]}"#, #"{"code":"synthetic","urls":["https://one.example/path"]}"#, #"{"code":"synthetic","urls":["https://user:password@one.example"]}"#] {
      #expect(throws: RemoteError.invalidPairing) { try OpenCodePairingPayload.parse(value) }
    }
  }
  @Test func redemptionUsesJSONWithoutAnyExistingCredential() async throws {
    let transport = NativeResponseTransport(#"{"token":"new-native-token"}"#)
    let client = OpenCodePairingClient(transport:transport)
    let payload = try OpenCodePairingPayload.parse("https://one.example/auth/connect/\(code)")
    let result = try await client.redeem(payload, origin:payload.origins[0])
    #expect(result.token == "new-native-token")
    #expect(result.origin.absoluteString == "https://one.example")
    let request = try #require(await transport.firstRequest())
    #expect(request.url?.absoluteString == "https://one.example/auth/connect/\(code)")
    #expect(request.value(forHTTPHeaderField:"Accept") == "application/json")
    #expect(request.value(forHTTPHeaderField:"Authorization") == nil)
    #expect(request.httpMethod == "GET")
    #expect(!request.httpShouldHandleCookies)
  }
  @Test func redemptionCannotSendACodeToAnUnadvertisedOrigin() async throws {
    let transport = NativeResponseTransport(#"{"token":"new-native-token"}"#)
    let client = OpenCodePairingClient(transport:transport)
    let payload = try OpenCodePairingPayload.parse("https://one.example/auth/connect/\(code)")
    await #expect(throws:RemoteError.invalidPairing) { try await client.redeem(payload,origin:URL(string:"https://other.example")!) }
    #expect(await transport.requestCount() == 0)
  }
  @Test func expiredCodesAndHTMLResponsesDoNotProduceCredentials() async throws {
    let payload = try OpenCodePairingPayload.parse("https://one.example/auth/connect/\(code)")
    for (body,status,error) in [(#"{"_tag":"UnauthorizedError"}"#,401,RemoteError.unauthorized),("<html>login</html>",200,.invalidResponse),(#"{"token":""}"#,200,.invalidResponse),(#"{"token":"redirect-token"}"#,302,.unavailable)] {
      let client = OpenCodePairingClient(transport:NativeResponseTransport(body,status:status))
      await #expect(throws:error) { try await client.redeem(payload,origin:payload.origins[0]) }
    }
  }
  @Test func payloadAndTokenDiagnosticsDoNotPrintSecrets() async throws {
    let payload = try OpenCodePairingPayload.parse("https://one.example/auth/connect/\(code)")
    let token = try await OpenCodePairingClient(transport:NativeResponseTransport(#"{"token":"new-native-token"}"#)).redeem(payload,origin:payload.origins[0])
    #expect(!String(describing:payload).contains(code))
    #expect(!String(reflecting:payload).contains(code))
    #expect(!String(describing:token).contains("new-native-token"))
  }
}
