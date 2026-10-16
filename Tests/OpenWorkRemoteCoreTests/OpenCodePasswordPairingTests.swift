import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor PasswordPairingTransport:HTTPTransport {
  private let replies:[(String,Int)]
  private var requests:[URLRequest]=[]
  init(_ replies:[(String,Int)]){self.replies=replies}
  func data(for request:URLRequest)async throws->(Data,Int){
    requests.append(request)
    guard requests.count<=replies.count else{throw URLError(.badServerResponse)}
    let reply=replies[requests.count-1]
    return(Data(reply.0.utf8),reply.1)
  }
  func recorded()->[URLRequest]{requests}
}

@Suite struct OpenCodePasswordPairingTests {
  let origin=URL(string:"https://computer.example:9443")!
  let info=#"{"version":"2.0.29","urls":["https://different.example"],"paths":{"tmp":"/tmp/native"}}"#
  let issued=#"{"code":"synthetic_stock_code","expires_in":300}"#

  // A wrong path, leaked master credential on redemption, or persisted password
  // must break this stock native wire-contract test.
  @Test func stockPasswordIssuesAndRedeemsOnlyAtTheReviewedOrigin()async throws{
    let password="synthetic:server-password-🔒"
    let transport=PasswordPairingTransport([(info,200),(issued,200),(#"{"token":"ordinary-paired-token"}"#,200)])
    let client=OpenCodePairingClient(transport:transport)
    let payload=try await client.issueUsingServerPassword(origin:origin,password:password)
    let token=try await client.redeem(payload,origin:origin)
    #expect(payload.origins==[origin]);#expect(token.origin==origin)
    #expect(token.token=="ordinary-paired-token")
    let requests=await transport.recorded()
    #expect(requests.map{ $0.url?.absoluteString }==[
      "https://computer.example:9443/api/info",
      "https://computer.example:9443/api/pair",
      "https://computer.example:9443/auth/connect/synthetic_stock_code"])
    #expect(requests.map(\.httpMethod)==["GET","POST","GET"])
    let header="Basic "+Data(("opencode:"+password).utf8).base64EncodedString()
    #expect(requests.prefix(2).allSatisfy{$0.value(forHTTPHeaderField:"Authorization")==header})
    #expect(requests.last?.value(forHTTPHeaderField:"Authorization")==nil)
    #expect(requests.allSatisfy{!$0.httpShouldHandleCookies && $0.value(forHTTPHeaderField:"Accept")=="application/json"})
    #expect(!String(reflecting:payload).contains(password))
    #expect(!String(reflecting:token).contains(password))
  }

  @Test func unsafeOriginsAndInvalidPasswordsAreRejectedBeforeTransmission()async throws{
    let transport=PasswordPairingTransport([])
    let client=OpenCodePairingClient(transport:transport)
    for value in ["http://computer.example","https://name:secret@computer.example","https://computer.example/api/pair","https://computer.example?next=other","https://computer.example#fragment"]{
      await #expect(throws:RemoteError.invalidPairing){try await client.issueUsingServerPassword(origin:URL(string:value)!,password:"test-password")}
    }
    let checked=OpenCodePairingClient(transport:transport)
    for password in ["","contains\nnewline",String(repeating:"x",count:16_385)]{
      await #expect(throws:RemoteError.invalidPairing){try await checked.issueUsingServerPassword(origin:origin,password:password)}
    }
    #expect(await transport.recorded().isEmpty)
  }

  @Test func rejectedPasswordCannotIssueACode()async throws{
    let transport=PasswordPairingTransport([(#"{"_tag":"UnauthorizedError"}"#,401)])
    await #expect(throws:RemoteError.unauthorized){
      try await OpenCodePairingClient(transport:transport).issueUsingServerPassword(origin:origin,password:"incorrect-synthetic-password")
    }
    #expect(await transport.recorded().count==1)
  }

  @Test func unsupportedServerCannotIssueACode()async throws{
    let transport=PasswordPairingTransport([(info.replacingOccurrences(of:"2.0.29",with:"2.99.999"),200)])
    await #expect(throws:RemoteError.incompatible){
      try await OpenCodePairingClient(transport:transport).issueUsingServerPassword(origin:origin,password:"test-password")
    }
    #expect(await transport.recorded().count==1)
  }

  @Test func invalidIssueResponsesCannotBecomePairingPayloads()async throws{
    for body in [#"{"code":"","expires_in":300}"#,#"{"code":"bad/code","expires_in":300}"#,#"{"code":"synthetic","expires_in":0}"#,#"{"code":"synthetic","expires_in":301}"#,"<html>login</html>"]{
      let transport=PasswordPairingTransport([(info,200),(body,200)])
      await #expect(throws:RemoteError.invalidResponse){
        try await OpenCodePairingClient(transport:transport).issueUsingServerPassword(origin:origin,password:"test-password")
      }
      #expect(await transport.recorded().count==2)
    }
  }
}
