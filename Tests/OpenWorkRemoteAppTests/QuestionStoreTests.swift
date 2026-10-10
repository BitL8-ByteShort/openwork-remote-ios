import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private func fixtureQuestion() throws -> QuestionRequest {
  try JSONDecoder().decode(QuestionRequest.self, from: Data(#"{"id":"frm_test","sessionId":"ses_test","revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","supported":true,"reason":null,"fields":[{"key":"name","kind":"text","title":"Name","prompt":"What should it be called?","options":[],"custom":true}]}"#.utf8))
}
private actor QuestionReplyTransport: HTTPTransport {
  var writes = 0
  var lost = false
  var conflict = false
  var wait = false
  var continuation: CheckedContinuation<Void, Never>?
  func configure(lost: Bool = false, conflict: Bool = false, wait: Bool = false) {
    self.lost = lost; self.conflict = conflict; self.wait = wait
  }
  func count() -> Int { writes }
  func release() { continuation?.resume(); continuation = nil }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    writes += 1
    if wait { await withCheckedContinuation { continuation = $0 } }
    if lost { throw RemoteError.unavailable }
    if conflict { return (Data("{}".utf8), 409) }
    let body = try JSONDecoder().decode(QuestionSubmission.self, from: request.httpBody!)
    return (Data("{\"data\":{\"requestId\":\"\(body.requestId)\",\"resourceId\":\"frm_test\",\"state\":\"accepted\",\"observedAt\":\"now\"},\"cursor\":null}".utf8), 200)
  }
}
@MainActor @Suite struct QuestionStoreTests {
  private func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: "question-tests-" + UUID().uuidString) }
  private func context() -> QuestionContext { QuestionContext(hostId: "fixture", workspaceId: "ws_test", sessionId: "ses_test", generation: UUID(), selection: UUID()) }
  @Test func noDefaultAndDraftSurvivesClosingAndRelaunch() async throws {
    let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let q = try fixtureQuestion(), c = context(), store = QuestionStore(directory: folder)
    try await store.restore()
    store.activate(c); store.apply([q], context: c)
    #expect(store.answers(for: q).isEmpty)
    #expect(!store.canReply(q))
    store.setAnswer(.string("Draft project"), field: "name", question: q)
    let id = store.draft(for: q)?.requestId
    try await store.persist()
    store.activate(nil)
    let reopened = QuestionStore(directory: folder)
    try await reopened.restore()
    reopened.activate(c); reopened.apply([q], context: c)
    #expect(reopened.answers(for: q)["name"] == .string("Draft project"))
    #expect(reopened.draft(for: q)?.requestId == id)
  }
  @Test func lostReplyRetainsIntentAndNeverResendsEvenAfterFormDisappears() async throws {
    let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let q = try fixtureQuestion(), c = context(), store = QuestionStore(directory: folder), transport = QuestionReplyTransport()
    try await store.restore(); store.activate(c); store.apply([q], context: c)
    store.setAnswer(.string("Draft project"), field: "name", question: q)
    let id = store.draft(for: q)?.requestId
    await transport.configure(lost: true)
    let client = try BridgeClient(origin: URL(string: "https://fixture.example.test")!, transport: transport)
    await store.submit(q, client: client, context: c)
    #expect(store.draft(for: q)?.state == .uncertain)
    store.apply([], context: c)
    #expect(store.hasUncertainReply)
    await store.submit(q, client: client, context: c)
    #expect(await transport.count() == 1)
    let reopened = QuestionStore(directory: folder); try await reopened.restore()
    reopened.activate(c); reopened.apply([q], context: c)
    #expect(reopened.draft(for: q)?.requestId == id)
    #expect(!reopened.canReply(q))
  }
  @Test func staleFormRetainsDraftAndRequiresLatestRequest() async throws {
    let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let q = try fixtureQuestion(), c = context(), store = QuestionStore(directory: folder), transport = QuestionReplyTransport()
    try await store.restore(); store.activate(c); store.apply([q], context: c)
    store.setAnswer(.string("Draft project"), field: "name", question: q)
    await transport.configure(conflict: true)
    await store.submit(q, client: try BridgeClient(origin: URL(string: "https://fixture.example.test")!, transport: transport), context: c)
    #expect(store.draft(for: q)?.state == .changed)
    #expect(store.answers(for: q)["name"] == .string("Draft project"))
    #expect(!store.canReply(q))
  }
  @Test func lateReplyCannotAffectAnotherChatOrNewPairing() async throws {
    let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let q = try fixtureQuestion(), c = context(), store = QuestionStore(directory: folder), transport = QuestionReplyTransport()
    try await store.restore(); store.activate(c); store.apply([q], context: c)
    store.setAnswer(.string("Draft project"), field: "name", question: q)
    await transport.configure(wait: true)
    let client = try BridgeClient(origin: URL(string: "https://fixture.example.test")!, transport: transport)
    let task = Task { await store.submit(q, client: client, context: c) }
    while await transport.count() == 0 { await Task.yield() }
    let next = context(); store.activate(next); store.apply([], context: next)
    await transport.release(); await task.value
    #expect(store.context == next)
    #expect(store.pending.isEmpty)
    #expect(store.notice == nil)
    store.apply([q], context: c)
    #expect(store.pending.isEmpty)
  }
  @Test func answeredOnComputerRemovesPendingWithoutInventingSuccess() async throws {
    let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let q = try fixtureQuestion(), c = context(), store = QuestionStore(directory: folder)
    try await store.restore(); store.activate(c); store.apply([q], context: c)
    store.setAnswer(.string("Draft project"), field: "name", question: q)
    store.apply([], context: c)
    #expect(!store.isCurrent(q))
    #expect(store.answers(for: q)["name"] == .string("Draft project"))
    #expect(store.draft(for: q)?.state == .editing)
  }
  @Test func failedPersistenceNeverLetsTheAnswerLeaveThePhone() async throws {
    let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let q = try fixtureQuestion(), c = context(), store = QuestionStore(directory: folder), transport = QuestionReplyTransport()
    try await store.restore(); store.activate(c); store.apply([q], context: c)
    store.setAnswer(.string("Draft project"), field: "name", question: q)
    try await store.persist()
    try FileManager.default.removeItem(at: folder)
    await store.submit(q, client: try BridgeClient(origin: URL(string: "https://fixture.example.test")!, transport: transport), context: c)
    #expect(await transport.count() == 0)
    #expect(store.draft(for: q)?.state == .editing)
  }
  @Test func crashDuringReplyRestoresAnUncertainIntentWithTheSameUUID() async throws {
    let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let q = try fixtureQuestion(), c = context(), store = QuestionStore(directory: folder), transport = QuestionReplyTransport()
    try await store.restore(); store.activate(c); store.apply([q], context: c)
    store.setAnswer(.string("Draft project"), field: "name", question: q)
    let id = store.draft(for: q)?.requestId
    await transport.configure(wait: true)
    let client = try BridgeClient(origin: URL(string: "https://fixture.example.test")!, transport: transport)
    let task = Task { await store.submit(q, client: client, context: c) }
    while await transport.count() == 0 { await Task.yield() }
    let recovered = QuestionStore(directory: folder); try await recovered.restore()
    recovered.activate(c); recovered.apply([q], context: c)
    #expect(recovered.draft(for: q)?.requestId == id)
    #expect(recovered.draft(for: q)?.state == .uncertain)
    #expect(!recovered.canReply(q))
    await transport.release(); await task.value
  }
}
