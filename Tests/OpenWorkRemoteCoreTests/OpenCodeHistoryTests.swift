import Foundation
import Testing
@testable import OpenWorkRemoteCore

actor NativeHistoryTransport: HTTPTransport {
  var requests: [URLRequest] = []
  func data(for request: URLRequest) async throws -> (Data,Int) {
    requests.append(request)
    let c = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
    if c.path == "/api/project" {
      return (Data(#"[{"id":"project","canonical":"/home/test/project","name":"Project","sandboxes":[],"time":{"created":1,"updated":2,"active":2}}]"#.utf8),200)
    }
    if c.path == "/api/session" {
      return (Data(#"{"data":[{"id":"ses_test","projectID":"project","title":"Synthetic chat","location":{"directory":"/home/test/project/worktree"},"time":{"created":1,"updated":2}}],"cursor":{"next":"opaque+next/="}}"#.utf8),200)
    }
    let cursor=c.queryItems?.first{$0.name=="cursor"}?.value
    let range:Range<Int> = cursor == "page_two" ? 5..<105 : cursor == "page_three" ? 0..<5 : 105..<205
    let messages = range.reversed().map { index -> [String:Any] in
      if index == 100 { return ["id":"msg_100","type":"compaction","time":["created":100],"summary":"Synthetic summary","status":"completed"] }
      return ["id":"msg_\(index)","type":"user","time":["created":index],"text":"Synthetic text \(index)","files":[],"agents":[],"skills":[]]
    }
    let next: [String:String] = cursor == "page_three" ? [:] : ["next":cursor == "page_two" ? "page_three" : "page_two"]
    return (try JSONSerialization.data(withJSONObject:["data":messages,"cursor":next]),200)
  }
  func paths() -> [String] { requests.compactMap{$0.url?.path} }
  func allRequests() -> [URLRequest] { requests }
}
@Suite struct OpenCodeHistoryTests {
  func client(_ transport:any HTTPTransport) throws -> OpenCodeClient {
    try OpenCodeClient(connection:OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer"),token:"synthetic-token",transport:transport)
  }
  @Test func projectsAndSessionDirectoryUseNativeFieldsAndOpaqueCursor() async throws {
    let transport=NativeHistoryTransport(), client=try client(transport)
    let projects=try await client.projects()
    #expect(projects.first?.canonical == "/home/test/project")
    let page=try await client.sessions(projectID:"project",cursor:nil,search:nil)
    #expect(page.data.first?.location.directory == "/home/test/project/worktree")
    #expect(page.cursor.next == "opaque+next/=")
    _ = try await client.sessions(projectID:"project",cursor:page.cursor.next,search:nil)
    let request=try #require(await transport.allRequests().last)
    let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems
    #expect(query?.first{$0.name=="cursor"}?.value == "opaque+next/=")
    #expect(query?.contains{$0.name=="order"} == false)
  }
  @Test func all205MessagesRemainReachableAcrossCompaction() async throws {
    let transport=NativeHistoryTransport(), client=try client(transport)
    var cursor:String?, messages:[OpenCodeMessage]=[]
    repeat {
      let page=try await client.messages(sessionID:"ses_test",cursor:cursor)
      messages.append(contentsOf:page.data);cursor=page.cursor.next
    } while cursor != nil
    #expect(messages.count == 205)
    #expect(Set(messages.map(\.id)).count == 205)
    #expect(messages.last?.text == "Synthetic text 0")
    #expect(messages.contains{$0.type == "compaction"})
    #expect(await transport.paths() == Array(repeating:"/api/session/ses_test/message",count:3))
  }
  @Test func assistantTextAndToolsKeepTheirNativeOrderWithSafeUnknownFallbacks() async throws {
    let body=#"{"data":[{"id":"msg_a","type":"assistant","time":{"created":1},"content":[{"type":"text","text":"Before"},{"type":"tool","id":"tool_1","name":"read","state":{"status":"completed","input":{},"content":[{"type":"text","text":"Synthetic output"}]}},{"type":"text","text":"Final answer"}]},{"id":"msg_new","type":"future-server-kind","time":{"created":2},"secret":"do not render raw fields"}],"cursor":{}}"#
    let page=try await client(NativeResponseTransport(body)).messages(sessionID:"ses_test",cursor:nil)
    #expect(page.data[0].content.map(\.type) == ["text","tool","text"])
    #expect(page.data[0].content.last?.text == "Final answer")
    #expect(page.data[0].content[1].toolName == "read")
    #expect(page.data[1].displayNotice == "This item is available on your computer.")
    #expect(page.data[1].text == nil)
  }
  @Test func aWrongProjectOrMalformedMessageDoesNotBecomeTheSelectedHistory() async throws {
    let wrong=#"{"data":[{"id":"ses_other","projectID":"different","location":{"directory":"/project"},"time":{"created":1,"updated":2}}],"cursor":{}}"#
    await #expect(throws:RemoteError.invalidResponse) { _ = try await client(NativeResponseTransport(wrong)).sessions(projectID:"project",cursor:nil,search:nil) }
    let bad=#"{"data":[{"id":"msg_broken","type":"user","time":{"created":1}}],"cursor":{}}"#
    await #expect(throws:RemoteError.invalidResponse) { _ = try await client(NativeResponseTransport(bad)).messages(sessionID:"ses_test",cursor:nil) }
  }
  @Test func locationPreservesProjectAndWorktreeRatherThanGuessingCanonicalDirectory() async throws {
    let body=#"{"directory":"/projects/C++/worktree","project":{"id":"project","directory":"/projects/C++/worktree","canonical":"/projects/C++"}}"#
    let transport=NativeResponseTransport(body), client=try client(transport)
    let location=try await client.location(directory:"/projects/C++/worktree")
    #expect(location.directory == "/projects/C++/worktree")
    #expect(location.project.canonical == "/projects/C++")
    let request=try #require(await transport.firstRequest())
    let url=try #require(request.url)
    #expect(URLComponents(url:url,resolvingAgainstBaseURL:false)?.percentEncodedQuery?.contains("%2B%2B") == true)
  }
  @Test func defaultLocationIsExplicitAndMismatchedResolutionIsRejected() async throws {
    let body=#"{"directory":"/home/test/notes","project":{"id":"global","directory":"/home/test/notes","canonical":"/"}}"#
    let transport=NativeResponseTransport(body), client=try client(transport)
    let location=try await client.location(directory:nil)
    #expect(location.directory == "/home/test/notes")
    #expect(location.project.canonical == "/")
    #expect(await transport.firstRequest()?.url?.query == nil)
    await #expect(throws:RemoteError.conflict) { _ = try await client.location(directory:"/different") }
  }
}
