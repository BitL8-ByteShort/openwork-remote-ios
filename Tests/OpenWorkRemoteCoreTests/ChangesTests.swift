import Foundation
import Testing
@testable import OpenWorkRemoteCore

private let revision = String(repeating: "a", count: 64)
private let handle = "chg_" + String(repeating: "b", count: 32)
private let refJSON = #"{"id":"chg_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","pathLabel":"src/home.tsx","status":"modified","binary":false,"added":1,"removed":1}"#
private func catalogJSON(_ files: String = refJSON, session: String = "ses_chat") -> String {
  "{\"revision\":\"\(revision)\",\"sessionId\":\"\(session)\",\"provenance\":\"workspace\",\"files\":[\(files)],\"moreOnComputer\":false}"
}
private func diffJSON(text: String = "--- a/src/home.tsx\n+++ b/src/home.tsx\n@@ -1 +1 @@\n-before\n+after\n", binary: Bool = false, omitted: Bool = false, id: String = handle, rev: String = revision) throws -> Data {
  try JSONSerialization.data(withJSONObject: ["revision":rev,"changeId":id,"binary":binary,"text":text,"omitted":omitted])
}
private actor ChangeTransport: HTTPTransport {
  private var requests: [URLRequest] = []
  private var catalog = catalogJSON()
  private var diffData = try! diffJSON()
  private var lost = false
  func configure(catalog: String? = nil, diff: Data? = nil, lost: Bool = false) { if let catalog { self.catalog = catalog }; if let diff { diffData = diff }; self.lost = lost }
  func captured() -> [URLRequest] { requests }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    requests.append(request); if lost { throw RemoteError.unavailable }
    let data = request.url!.path.hasSuffix("/diff") ? diffData : Data(catalog.utf8)
    let value = try JSONSerialization.jsonObject(with:data)
    return (try JSONSerialization.data(withJSONObject:["data":value,"cursor":NSNull()]),200)
  }
}
@Suite struct ChangesTests {
  @Test func changeReferencesRejectPathsCountsAndUnknownFields() throws {
    #expect(try JSONDecoder().decode(ChangeRef.self,from:Data(refJSON.utf8)).status == .modified)
    for json in [refJSON.dropLast()+",\"root\":\"/secret\"}", refJSON.replacingOccurrences(of:"src/home.tsx",with:"../secret"),
      refJSON.replacingOccurrences(of:"src/home.tsx",with:"/etc/passwd"),refJSON.replacingOccurrences(of:"src/home.tsx",with:".git/config"),
      refJSON.replacingOccurrences(of:"\"added\":1",with:"\"added\":-1"), refJSON.replacingOccurrences(of:handle,with:"filename.txt") ] {
      #expect(throws:(any Error).self) { try JSONDecoder().decode(ChangeRef.self,from:Data(json.utf8)) }
    }
  }
  @Test func catalogsAreBoundedUniqueAndHonestlyWorkspaceDerived() throws {
    #expect(try JSONDecoder().decode(ChangeSet.self,from:Data(catalogJSON().utf8)).provenance == "workspace")
    for json in [catalogJSON(refJSON+","+refJSON),catalogJSON().replacingOccurrences(of:"workspace",with:"session"),
      catalogJSON().replacingOccurrences(of:revision,with:"bad"),catalogJSON().dropLast()+",\"unavailableReason\":\"non_git\"}",
      catalogJSON(Array(repeating:refJSON,count:101).joined(separator:","))] {
      #expect(throws:(any Error).self) { try JSONDecoder().decode(ChangeSet.self,from:Data(json.utf8)) }
    }
  }
  @Test func diffPayloadsRejectMisleadingBinaryOrUnboundedText() throws {
    #expect(try JSONDecoder().decode(FileDiff.self,from:diffJSON()).omitted == false)
    for data in [try diffJSON(binary:true),try diffJSON(text:String(repeating:"é",count:524289)),try diffJSON(text:String(repeating:"line\n",count:10001)),
      try diffJSON(id:"/secret"),try diffJSON(rev:"bad")] {
      #expect(throws:(any Error).self) { try JSONDecoder().decode(FileDiff.self,from:data) }
    }
  }
  @Test func transportUsesOnlyPairedOriginAndChecksReturnedChatHandleAndRevision() async throws {
    let transport=ChangeTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test:9443")!,token:"synthetic",transport:transport)
    let catalog=try await client.changes("ws_owned","ses_chat"),ref=try #require(catalog.files.first)
    #expect(try await client.diff("ws_owned","ses_chat",ref:ref,revision:catalog.revision).text.contains("+after"))
    let requests=await transport.captured()
    #expect(requests.map(\.httpMethod) == ["GET","GET"])
    #expect(requests.last?.url?.absoluteString == "https://fixture.test:9443/v1/workspaces/ws_owned/sessions/ses_chat/changes/\(handle)/diff?revision=\(revision)")
    #expect(requests.allSatisfy{$0.value(forHTTPHeaderField:"Authorization") == "Bearer synthetic"})
    await #expect(throws:RemoteError.invalidResponse) { try await client.changes("ws_owned","ses_other") }
    await transport.configure(diff:try diffJSON(rev:String(repeating:"c",count:64)))
    await #expect(throws:RemoteError.invalidResponse) { try await client.diff("ws_owned","ses_chat",ref:ref,revision:revision) }
    await transport.configure(diff:try diffJSON(id:"chg_"+String(repeating:"c",count:32)))
    await #expect(throws:RemoteError.invalidResponse) { try await client.diff("ws_owned","ses_chat",ref:ref,revision:revision) }
  }
  @Test func invalidRequestsAndUncertainReadsNeverRetryAutomatically() async throws {
    let transport=ChangeTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.test")!,transport:transport)
    let ref=try JSONDecoder().decode(ChangeRef.self,from:Data(refJSON.utf8))
    await #expect(throws:RemoteError.invalidResponse) { try await client.diff("ws_owned","ses_chat",ref:ref,revision:"bad") }
    #expect(await transport.captured().isEmpty)
    await transport.configure(lost:true)
    await #expect(throws:RemoteError.unavailable) { try await client.changes("ws_owned","ses_chat") }
    #expect(await transport.captured().count == 1)
  }
}
extension ChangesTests {
  @Test func passiveDiffLinesSeparateHeadersFromAdditionsAndBoundLongUnicodeLines() {
    let lines=DiffLine.parse("--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+<script>literal text</script>\n unchanged\n")
    #expect(lines.map(\.kind) == [.header,.header,.header,.removal,.addition,.context])
    #expect(lines.last?.text == " unchanged")
    let long=DiffLine.parse("+"+String(repeating:"é",count:10000))
    #expect(long.first?.shortened == true);#expect((long.first?.text.utf8.count ?? Int.max) <= 8000)
  }
}
