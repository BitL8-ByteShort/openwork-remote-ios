import Foundation

public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, Int)
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error>
}
extension HTTPTransport {
  public func events(for request: URLRequest) async throws -> AsyncThrowingStream<
    SSEFrame, any Error
  > { throw RemoteError.unavailable }
}
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
public actor SessionTransport: HTTPTransport {
  private let session: URLSession
  public init() {
    let c = URLSessionConfiguration.ephemeral
    c.httpShouldSetCookies = false
    c.urlCache = nil
    c.requestCachePolicy = .reloadIgnoringLocalCacheData
    c.timeoutIntervalForRequest = 45
    c.timeoutIntervalForResource = 86400
    session = URLSession(configuration: c, delegate: RedirectBlocker(), delegateQueue: nil)
  }
  public func data(for request: URLRequest) async throws -> (Data, Int) {
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw RemoteError.invalidResponse }
    guard response.expectedContentLength <= 8_388_608 else { throw RemoteError.oversized }
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > 8_388_608 { throw RemoteError.oversized }
    }
    return (data, http.statusCode)
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
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
      let task = Task {
        var parser = SSEParser()
        var chunk = Data()
        do {
          for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if byte == 10 || chunk.count >= 4096 {
              for event in try parser.push(chunk) {
                guard
                  event.data.utf8.count + (event.id?.utf8.count ?? 0)
                    + event.event.utf8.count <= 16384
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
public actor BridgeClient {
  public let origin: URL
  private let token: String?
  private let transport: any HTTPTransport
  public init(origin: URL, token: String? = nil, transport: any HTTPTransport = SessionTransport())
    throws
  {
    self.origin = try PairingValidation.origin(origin.absoluteString)
    self.token = token
    self.transport = transport
  }
  private func request(_ path: String, method: String = "GET", body: Data? = nil) throws
    -> URLRequest
  {
    guard path.hasPrefix("/v1/"), !path.contains(".."),
      var c = URLComponents(url: origin, resolvingAgainstBaseURL: false)
    else { throw RemoteError.invalidResponse }
    let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    c.percentEncodedPath = String(pieces[0])
    c.percentEncodedQuery = pieces.count > 1 ? String(pieces[1]) : nil
    guard let url = c.url, url.host == origin.host, url.scheme == "https", url.port == origin.port
    else { throw RemoteError.invalidResponse }
    var r = URLRequest(url: url)
    r.httpMethod = method
    r.httpBody = body
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    return r
  }
  private func check(_ status: Int) throws {
    switch status {
    case 200...299: return
    case 401: throw RemoteError.unauthorized
    case 403: throw RemoteError.forbidden
    case 404: throw RemoteError.notFound
    case 409: throw RemoteError.conflict
    case 413: throw RemoteError.oversized
    case 422: throw RemoteError.incompatible
    default: throw RemoteError.unavailable
    }
  }
  private func decode<T: Decodable & Sendable>(
    _ type: T.Type, path: String, method: String = "GET", body: Data? = nil
  ) async throws -> T {
    let (data, status) = try await transport.data(for: request(path, method: method, body: body))
    try check(status)
    do { return try JSONDecoder().decode(T.self, from: data) } catch {
      throw RemoteError.invalidResponse
    }
  }
  private func id(_ value: String) throws -> String {
    guard value.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil else {
      throw RemoteError.invalidResponse
    }
    return value
  }
  private func base(_ wid: String, _ sid: String) throws -> String {
    "/v1/workspaces/" + (try id(wid)) + "/sessions/" + (try id(sid))
  }
  private func cursor(_ value: String?) throws -> String {
    guard let value else { return "" }
    guard value.utf8.count <= 4096 else { throw RemoteError.oversized }
    var c = URLComponents()
    c.queryItems = [URLQueryItem(name: "cursor", value: value)]
    return "?" + c.percentEncodedQuery!
  }
  public func host() async throws -> Host {
    try await decode(Envelope<Host>.self, path: "/v1/host").data
  }
  public func workspaces() async throws -> Envelope<[Workspace]> {
    try await decode(Envelope<[Workspace]>.self, path: "/v1/workspaces")
  }
  public func sessions(_ wid: String, cursor value: String? = nil) async throws -> Envelope<
    [ChatSession]
  > {
    try await decode(
      Envelope<[ChatSession]>.self,
      path: "/v1/workspaces/" + (try id(wid)) + "/sessions" + (try cursor(value)))
  }
  public func session(_ wid: String, _ sid: String) async throws -> ChatSession {
    try await decode(Envelope<ChatSession>.self, path: try base(wid, sid)).data
  }
  public func rename(_ wid: String, _ sid: String, title: String, previousTitle: String, requestId: UUID) async throws -> MutationReceipt {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title.unicodeScalars.count <= 200 else { throw RemoteError.invalidResponse }
    return try await decode(Envelope<MutationReceipt>.self,
      path: (try base(wid, sid)) + "/rename", method: "POST",
      body: JSONEncoder().encode(["requestId": requestId.uuidString.lowercased(), "title": title, "previousTitle": previousTitle])).data
  }
  public func messages(_ wid: String, _ sid: String, cursor value: String? = nil) async throws
    -> Envelope<[ChatMessage]>
  {
    try await decode(
      Envelope<[ChatMessage]>.self, path: (try base(wid, sid)) + "/messages" + (try cursor(value)))
  }
  public func status(_ wid: String, _ sid: String) async throws -> SessionStatus {
    try await decode(Envelope<SessionStatus>.self, path: (try base(wid, sid)) + "/status").data
  }
  public func approvals(_ wid: String, _ sid: String) async throws -> [Approval] {
    try await decode(Envelope<[Approval]>.self, path: (try base(wid, sid)) + "/approvals").data
  }
  public func questions(_ wid: String, _ sid: String) async throws -> [QuestionRequest] {
    let questions = try await decode(Envelope<[QuestionRequest]>.self,
      path: (try base(wid, sid)) + "/questions").data
    guard questions.count <= 32, Set(questions.map(\.id)).count == questions.count else {
      throw RemoteError.invalidResponse
    }
    for question in questions { try question.validateShape(sessionId: sid) }
    return questions
  }
  public func replyQuestion(_ wid: String, _ sid: String, question: QuestionRequest,
    answers: QuestionAnswers, requestId: UUID) async throws -> MutationReceipt {
    try question.validateShape(sessionId: sid)
    try question.validate(answers: answers)
    return try await settleQuestion(wid, sid, question: question, answers: answers, requestId: requestId, action: "reply")
  }
  public func dismissQuestion(_ wid: String, _ sid: String, question: QuestionRequest,
    requestId: UUID) async throws -> MutationReceipt {
    try question.validateShape(sessionId: sid)
    guard question.supported else { throw RemoteError.incompatible }
    return try await settleQuestion(wid, sid, question: question, answers: nil, requestId: requestId, action: "dismiss")
  }
  private func settleQuestion(_ wid: String, _ sid: String, question: QuestionRequest,
    answers: QuestionAnswers?, requestId: UUID, action: String) async throws -> MutationReceipt {
    let receipt = try await decode(Envelope<MutationReceipt>.self,
      path: (try base(wid, sid)) + "/questions/" + (try id(question.id)) + "/" + action,
      method: "POST", body: JSONEncoder().encode(QuestionSubmission(requestId: requestId, revision: question.revision, answers: answers))).data
    guard receipt.requestId == requestId.uuidString.lowercased(), receipt.resourceId == question.id,
      ["accepted", "confirmed", "outcome_unknown"].contains(receipt.state) else { throw RemoteError.invalidResponse }
    return receipt
  }
  public func send(_ intent: SendIntent) async throws -> MutationReceipt {
    let body = try JSONEncoder().encode([
      "requestId": intent.requestId.uuidString.lowercased(), "text": intent.text,
    ])
    return try await decode(
      Envelope<MutationReceipt>.self,
      path: (try base(intent.key.workspaceId, intent.key.sessionId)) + "/messages", method: "POST",
      body: body
    ).data
  }
  public func stop(_ wid: String, _ sid: String, requestId: UUID) async throws -> MutationReceipt {
    try await decode(
      Envelope<MutationReceipt>.self, path: (try base(wid, sid)) + "/stop", method: "POST",
      body: JSONEncoder().encode(["requestId": requestId.uuidString.lowercased()])
    ).data
  }
  public func replyApproval(_ wid: String, _ sid: String, approval: Approval, decision: String, requestId: UUID) async throws -> MutationReceipt {
    guard ["allowOnce", "deny"].contains(decision), approval.sessionId == sid,
      approval.supportedDecisions.contains(decision) else { throw RemoteError.incompatible }
    return try await decode(Envelope<MutationReceipt>.self,
      path: (try base(wid, sid)) + "/approvals/" + (try id(approval.id)) + "/reply", method: "POST",
      body: JSONEncoder().encode(["requestId": requestId.uuidString.lowercased(), "decision": decision, "revision": approval.revision])).data
  }
  public func deviceAccess() async throws -> DeviceAccess {
    try await decode(Envelope<DeviceAccess>.self, path: "/v1/device/access").data
  }
  public func modelSettings(_ wid: String, _ sid: String) async throws -> ModelSettings {
    try await decode(Envelope<ModelSettings>.self, path: (try base(wid, sid)) + "/model-settings").data
  }
  public func setModel(_ wid: String, _ sid: String, model: ModelSelection, revision: String, requestId: UUID) async throws -> MutationReceipt {
    struct Body: Encodable { let requestId: String; let revision: String; let model: ModelSelection }
    return try await decode(Envelope<MutationReceipt>.self, path: (try base(wid, sid)) + "/model-settings", method: "POST", body: JSONEncoder().encode(Body(requestId: requestId.uuidString.lowercased(), revision: revision, model: model))).data
  }
  public func savedPermissions(_ wid: String, _ sid: String) async throws -> SavedPermissions {
    try await decode(Envelope<SavedPermissions>.self, path: (try base(wid, sid)) + "/permissions").data
  }
  public func revokePermission(_ wid: String, _ sid: String, permission: SavedPermission, requestId: UUID) async throws -> MutationReceipt {
    try await decode(Envelope<MutationReceipt>.self, path: (try base(wid, sid)) + "/permissions/" + (try id(permission.id)) + "/revoke", method: "POST", body: JSONEncoder().encode(["requestId": requestId.uuidString.lowercased(), "revision": permission.revision])).data
  }
  public func create(_ wid: String, requestId: UUID) async throws -> MutationReceipt {
    try await decode(
      Envelope<MutationReceipt>.self, path: "/v1/workspaces/" + (try id(wid)) + "/sessions",
      method: "POST", body: JSONEncoder().encode(["requestId": requestId.uuidString.lowercased()])
    ).data
  }
  public func claim(_ payload: PairingPayload, deviceId: String, deviceName: String) async throws
    -> PairClaim
  {
    struct Body: Encodable {
      let pairingId: String
      let secret: String
      let deviceId: String
      let deviceName: String
      let protocolVersion: Int
    }
    return try await decode(
      Envelope<PairClaim>.self, path: "/v1/pairings/claim", method: "POST",
      body: JSONEncoder().encode(
        Body(
          pairingId: payload.pairingId, secret: payload.secret, deviceId: deviceId,
          deviceName: deviceName, protocolVersion: 1))
    ).data
  }
  public func poll(_ claim: PairClaim) async throws -> PairPoll {
    try await decode(
      Envelope<PairPoll>.self, path: "/v1/pairings/poll", method: "POST",
      body: JSONEncoder().encode(["claimId": claim.claimId, "pollToken": claim.pollToken])
    ).data
  }
  public func ack() async throws {
    let (_, status) = try await transport.data(
      for: request("/v1/pairings/ack", method: "POST", body: Data("{}".utf8)))
    try check(status)
  }
  public func revoke() async throws {
    let (_, status) = try await transport.data(for: request("/v1/device", method: "DELETE"))
    try check(status)
  }
  public func events(cursor: String?) async throws -> AsyncThrowingStream<SSEFrame, any Error> {
    var r = try request("/v1/events")
    r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    if let cursor { r.setValue(cursor, forHTTPHeaderField: "Last-Event-ID") }
    return try await transport.events(for: r)
  }
}
