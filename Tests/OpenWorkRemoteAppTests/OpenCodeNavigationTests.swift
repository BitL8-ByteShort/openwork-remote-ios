import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor NativeNavigationReader: OpenCodeHistoryReading {
  let label:String
  let delay:Duration
  let moved:Bool
  let sameTime:Bool
  init(_ label:String="Synthetic",delay:Duration = .zero,moved:Bool=false,sameTime:Bool=false) { self.label=label;self.delay=delay;self.moved=moved;self.sameTime=sameTime }
  func projects() async throws -> [OpenCodeProject] {
    try JSONDecoder().decode([OpenCodeProject].self,from:Data(#"[{"id":"project","canonical":"/project","name":"Project","sandboxes":[],"time":{"created":1,"updated":2,"active":2}}]"#.utf8))
  }
  func sessions(projectID:String,cursor:String?,search:String?) async throws -> OpenCodeSessionPage {
    try JSONDecoder().decode(OpenCodeSessionPage.self,from:Data(#"{"data":[{"id":"ses_chat","projectID":"project","title":"Chat","location":{"directory":"/project"},"time":{"created":1,"updated":2}}],"cursor":{}}"#.utf8))
  }
  func session(id:String) async throws -> OpenCodeSession {
    let path = moved ? "/moved" : "/project"
    return try JSONDecoder().decode(OpenCodeSession.self,from:Data("{\"id\":\"\(id)\",\"projectID\":\"project\",\"title\":\"Chat\",\"location\":{\"directory\":\"\(path)\"},\"time\":{\"created\":1,\"updated\":2}}".utf8))
  }
  func messages(sessionID:String,cursor:String?) async throws -> OpenCodeMessagePage {
    try await Task.sleep(for:delay)
    let range = cursor == nil ? 3..<6 : 0..<4
    let order = sameTime ? [5,3,4] : Array(range.reversed())
    let data=order.map{["id":"msg_\($0)","type":"user","text":"\(label) \($0)","time":["created":sameTime ? 1 : $0]] as [String:Any]}
    return try JSONDecoder().decode(OpenCodeMessagePage.self,from:JSONSerialization.data(withJSONObject:["data":data,"cursor":cursor == nil ? ["next":"older"] : [:]]))
  }
}
@Suite @MainActor struct OpenCodeNavigationTests {
  func connection() throws -> OpenCodeConnection { try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer") }
  @Test func chatSelectionIsImmediateWhileHistoryLoads() async throws {
    let store=OpenCodeNavigationStore()
    store.activate(try connection(),reader:NativeNavigationReader(delay:.milliseconds(70)))
    await store.refreshProjects()
    let row=try #require(store.sessions.first)
    let task=Task { await store.open(row) }
    await Task.yield()
    #expect(store.selectedSession?.id == row.id)
    #expect(store.loadingMessages)
    await task.value
    #expect(store.messages.count == 3)
    #expect(store.target?.directory == "/project")
  }
  @Test func aLateResponseFromAnotherComputerWithEqualChatIDIsIgnored() async throws {
    let store=OpenCodeNavigationStore(), a=try connection(), b=try connection()
    store.activate(a,reader:NativeNavigationReader("Old",delay:.milliseconds(80)))
    await store.refreshProjects()
    let row=try #require(store.sessions.first)
    let old=Task { await store.open(row) }
    await Task.yield()
    store.activate(b,reader:NativeNavigationReader("Current"))
    await store.refreshProjects();await store.open(try #require(store.sessions.first))
    await old.value
    #expect(store.target?.connectionID == b.id)
    #expect(store.messages.allSatisfy{$0.text?.hasPrefix("Current") == true})
  }
  @Test func aMovedSessionNeverGetsASendTargetForItsOldDirectory() async throws {
    let store=OpenCodeNavigationStore()
    store.activate(try connection(),reader:NativeNavigationReader(moved:true))
    await store.refreshProjects();await store.open(try #require(store.sessions.first))
    #expect(store.target == nil)
    #expect(store.issue == .locationChanged)
  }
  @Test func olderPagingDeduplicatesAndBoundsTheWindow() async throws {
    let store=OpenCodeNavigationStore(maximumMessages:4)
    store.activate(try connection(),reader:NativeNavigationReader())
    await store.refreshProjects();await store.open(try #require(store.sessions.first))
    await store.loadOlder()
    #expect(store.messages.map(\.id) == ["msg_0","msg_1","msg_2","msg_3"])
    #expect(store.windowTruncated)
    #expect(store.olderCursor == nil)
    #expect(store.preserveScrollAnchor == "msg_3")
  }
  @Test func serverOrderIsPreservedWhenMessageTimestampsMatch() async throws {
    let store=OpenCodeNavigationStore()
    store.activate(try connection(),reader:NativeNavigationReader(sameTime:true))
    await store.refreshProjects();await store.open(try #require(store.sessions.first))
    #expect(store.messages.map(\.id) == ["msg_4","msg_3","msg_5"])
  }
}
