import Foundation
import Observation
import OpenWorkRemoteCore

struct QuestionContext: Equatable, Sendable {
  let hostId: String
  let workspaceId: String
  let sessionId: String
  let generation: UUID
  let selection: UUID
}
struct QuestionDraftKey: Codable, Equatable, Sendable {
  let hostId: String
  let workspaceId: String
  let sessionId: String
  let questionId: String
  let revision: String
}
struct QuestionDraft: Codable, Sendable {
  enum State: String, Codable, Sendable { case editing, sending, sent, uncertain, changed, unavailable }
  let key: QuestionDraftKey
  var answers: QuestionAnswers = [:]
  var requestId = UUID()
  var state: State = .editing
  var dismiss = false
}
struct QuestionDiskState: Codable, Sendable { var drafts: [QuestionDraft] = [] }

@MainActor @Observable final class QuestionStore {
  private(set) var context: QuestionContext?
  private(set) var pending: [QuestionRequest] = []
  private(set) var notice: String?
  private(set) var ready = false
  private(set) var readFailed = false
  private var disk = QuestionDiskState()
  private var revision: UInt64 = 0
  private let directory: URL
  private let snapshots: RevisionedSnapshotStore<QuestionDiskState>
  private var readID = UUID()
  private var readRun = UUID()
  private var readTask: Task<Void, Never>?
  private var readAgain = false

  init(directory: URL? = nil) {
    let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "OpenWorkRemote", directoryHint: .isDirectory)
    self.directory = root
    snapshots = RevisionedSnapshotStore(url: root.appending(path: "questions.json"))
  }
  func restore() async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
    disk = try await snapshots.load() ?? QuestionDiskState()
    for i in disk.drafts.indices where disk.drafts[i].state == .sending { disk.drafts[i].state = .uncertain }
    ready = true
  }
  func activate(_ context: QuestionContext?) {
    guard self.context != context else { return }
    readTask?.cancel(); readTask = nil; readAgain = false
    readID = UUID(); readRun = UUID()
    self.context = context
    pending = []
    notice = nil
    readFailed = false
  }
  // Question fetches do not delay presentation of the already-loaded conversation.
  // Coalesce bursts into one current read plus one follow-up, rather than pile up requests.
  func scheduleRead(client: BridgeClient, context: QuestionContext) {
    activate(context)
    guard readTask == nil else { readAgain = true; return }
    let run = UUID(); readRun = run
    readTask = Task {
      defer { if readRun == run { readTask = nil } }
      repeat {
        readAgain = false
        await refresh(client: client, context: context)
      } while readAgain && self.context == context && !Task.isCancelled
    }
  }
  func refresh(client: BridgeClient, context: QuestionContext) async {
    guard self.context == context else { return }
    let id = UUID(); readID = id
    do {
      let questions = try await client.questions(context.workspaceId, context.sessionId)
      guard id == readID, !Task.isCancelled else { return }
      apply(questions, context: context)
    } catch {
      guard id == readID, !Task.isCancelled else { return }
      failedRead(context: context)
    }
  }
  func apply(_ questions: [QuestionRequest], context: QuestionContext) {
    guard self.context == context else { return }
    pending = questions
    readFailed = false
  }
  func failedRead(context: QuestionContext) {
    guard self.context == context else { return }
    readFailed = true
    notice = "Questions could not be checked. Reconnect or continue in OpenWork on your computer."
  }
  func isCurrent(_ question: QuestionRequest) -> Bool {
    pending.contains { $0.id == question.id && $0.revision == question.revision }
  }
  private func key(_ question: QuestionRequest, context: QuestionContext) -> QuestionDraftKey {
    QuestionDraftKey(hostId: context.hostId, workspaceId: context.workspaceId, sessionId: context.sessionId,
      questionId: question.id, revision: question.revision)
  }
  func draft(for question: QuestionRequest) -> QuestionDraft? {
    guard let context else { return nil }
    return disk.drafts.first { $0.key == key(question, context: context) }
  }
  func answers(for question: QuestionRequest) -> QuestionAnswers { draft(for: question)?.answers ?? [:] }
  var hasUncertainReply: Bool {
    guard let context else { return false }
    return disk.drafts.contains { $0.key.hostId == context.hostId && $0.key.workspaceId == context.workspaceId
      && $0.key.sessionId == context.sessionId && $0.state == .uncertain }
  }
  func canEdit(_ question: QuestionRequest) -> Bool {
    ready && question.supported && isCurrent(question) && (draft(for: question)?.state ?? .editing) == .editing
  }
  func canReply(_ question: QuestionRequest) -> Bool {
    canEdit(question) && (try? question.validate(answers: answers(for: question))) != nil
  }
  func setAnswer(_ answer: QuestionAnswer, field: String, question: QuestionRequest) {
    guard canEdit(question), question.fields.contains(where: { $0.key == field }), let context else { return }
    let key = key(question, context: context)
    var draft = disk.drafts.first { $0.key == key } ?? QuestionDraft(key: key)
    guard draft.answers[field] != answer else { return }
    draft.answers[field] = answer
    draft.requestId = UUID()
    put(draft)
    autosave()
  }
  private func put(_ draft: QuestionDraft) {
    if let i = disk.drafts.firstIndex(where: { $0.key == draft.key }) { disk.drafts[i] = draft }
    else { disk.drafts.append(draft) }
  }
  func persist() async throws {
    guard ready else { throw RemoteError.unavailable }
    revision += 1
    try await snapshots.save(disk, revision: revision)
  }
  private func autosave() {
    revision += 1
    let snapshot = disk, version = revision, current = context
    Task {
      do { try await snapshots.save(snapshot, revision: version) }
      catch { if context == current { notice = "Your answers could not be saved. Keep this sheet open until you copy them." } }
    }
  }
  func submit(_ question: QuestionRequest, client: BridgeClient, context: QuestionContext, dismiss: Bool = false) async {
    guard self.context == context, canEdit(question), dismiss || canReply(question) else { return }
    let key = key(question, context: context)
    var intent = disk.drafts.first { $0.key == key } ?? QuestionDraft(key: key)
    intent.dismiss = dismiss
    intent.state = .sending
    put(intent)
    notice = nil
    do { try await persist() } catch {
      intent.state = .editing; put(intent)
      if self.context == context { notice = "Your request could not be saved. No answer was sent." }
      return
    }
    guard self.context == context else {
      intent.state = .editing; put(intent); autosave(); return
    }
    do {
      let receipt = try await dismiss
        ? client.dismissQuestion(context.workspaceId, context.sessionId, question: question, requestId: intent.requestId)
        : client.replyQuestion(context.workspaceId, context.sessionId, question: question, answers: intent.answers, requestId: intent.requestId)
      intent.state = ["accepted", "confirmed"].contains(receipt.state) ? .sent : .uncertain
    } catch RemoteError.conflict { intent.state = .changed }
    catch RemoteError.notFound { intent.state = .unavailable }
    catch RemoteError.forbidden { intent.state = .unavailable }
    catch RemoteError.unauthorized { intent.state = .unavailable }
    catch RemoteError.incompatible { intent.state = .unavailable }
    catch { intent.state = .uncertain }
    put(intent)
    // Keep the old target's durable outcome without presenting it in another chat or pairing.
    if self.context == context {
      switch intent.state {
      case .sent: notice = dismiss ? "Question dismissed." : "Answers sent."
      case .uncertain: notice = "The answer is unconfirmed. Check this chat in OpenWork on your computer. It will not be sent again automatically."
      case .changed: notice = "This question changed on your computer. Close this sheet and review the latest request. Your draft is kept."
      case .unavailable: notice = "This question is no longer available to answer here. Check OpenWork on your computer. Your draft is kept."
      default: break
      }
    }
    do { try await persist() } catch {
      if self.context == context { notice = "The answer status could not be saved. Check OpenWork before answering again." }
    }
  }
}
