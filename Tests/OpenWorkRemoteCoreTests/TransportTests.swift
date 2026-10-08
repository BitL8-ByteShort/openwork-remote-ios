import Foundation
import Testing

@testable import OpenWorkRemoteCore

@Test func originRequiresNormalHTTPSAndNoEmbeddedSecrets() throws {
  #expect(
    try PairingValidation.origin("https://host.tail123.ts.net:9443").absoluteString
      == "https://host.tail123.ts.net:9443")
  for value in [
    "http://host.test", "https://user:secret@host.test", "https://host.test/path",
    "https://host.test/?token=secret", "https://host.test/#secret",
  ] { #expect(throws: (any Error).self) { try PairingValidation.origin(value) } }
}
@Test func splitUnicodeAndMultilineEventsArePreserved() throws {
  var parser = SSEParser()
  var frames: [SSEFrame] = []
  for byte in Data("id: epoch:1\r\nevent: change\r\ndata: 😀\r\ndata: two\r\n\r\n".utf8) {
    frames += try parser.push(Data([byte]))
  }
  #expect(frames == [SSEFrame(event: "change", id: "epoch:1", data: "😀\ntwo")])
}
@Test func parserRejectsAnOversizedIncompleteFrame() throws {
  var parser = SSEParser(limit: 8)
  #expect(throws: RemoteError.oversized) { try parser.push(Data("data: oversized".utf8)) }
}
