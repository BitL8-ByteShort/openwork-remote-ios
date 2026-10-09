import Foundation
import OSLog
import Observation
import OpenWorkRemoteCore

@MainActor @Observable final class AppModel {
  var connection: ConnectionState = .unpaired
  var host: OpenWorkRemoteCore.Host?
  var workspaces: [Workspace] = []
  var sessions: [ChatSession] = []
  var messages: [ChatMessage] = []
  var approvals: [Approval] = []
  var status: SessionStatus?
  private var directory = PagedSnapshot<ChatSession>()
  private var history = PagedSnapshot<ChatMessage>()
  var sessionCursor: String? { directory.cursor }
  var messageCursor: String? { history.cursor }
  var selectedWorkspace: String?
  var selectedSession: ChatSession?
  var disk = DiskState()
  var notice: String?
  var updatingControls = false
  var sending = false
  var loading = false
  var stopRequested = false
  var pairingError: String?
  var pendingPhone = false
  var onboardingStep = 0
  private let pairingPersistence: PairingPersistence
  private let transport: any HTTPTransport
  private var client: BridgeClient?
  private var storedPairing: StoredPairing?
  private var draftStore: DraftStore?
  private var connectionTask: Task<Void, Never>?
  private var pairingTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var refreshID: UUID?
  private var pairingGeneration = UUID()
  private var savedPendingPairing = false
  private var generation = UUID()
  private var selectionID = UUID()
  private var foreground = true
  private var saveRevision: UInt64 = 0
  var draft: String {
    get { disk.conversation.currentDraft }
    set {
      disk.conversation.setDraft(newValue)
      saveDrafts()
    }
  }
  var uncertain: Bool {
    disk.conversation.selected.map { disk.conversation.uncertain.contains($0) } ?? false
  }
  var canSend: Bool {
    connection == .ready && !sending && !updatingControls && !uncertain && selectedSession != nil
      && host?.capabilities.sendText == true && ["idle", "error"].contains(status?.phase ?? "")
      && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.utf8.count <= 32768
  }
  init(pairingPersistence: PairingPersistence = .keychain,
       transport: any HTTPTransport = SessionTransport(), draftStore: DraftStore? = nil) {
    self.pairingPersistence = pairingPersistence
    self.transport = transport
    self.draftStore = draftStore
  }
  func start() async {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding") { return }
    #endif
    do {
      if draftStore == nil { draftStore = try DraftStore() }
      disk = try await draftStore!.load()
      storedPairing = try pairingPersistence.load()
      if let p = storedPairing {
        client = try BridgeClient(origin: PairingValidation.origin(p.origin), token: p.token, transport: transport)
        connect()
      }
    } catch {
      notice = "Your saved connection or draft could not be opened. Unlock the phone and try again."
    }
  }
  func saveDrafts() {
    guard let draftStore else { return }
    saveRevision += 1
    let revision = saveRevision
    let state = disk
    Task {
      do { try await draftStore.save(state, revision: revision) } catch {
        notice = "Your draft could not be saved. Keep the app open until you copy it."
      }
    }
  }
  func connect() {
    if connection == .revoked {
      pairAgain()
      return
    }
    guard let client else {
      connection = .unpaired
      return
    }
    connectionTask?.cancel()
    refreshTask?.cancel()
    refreshTask = nil
    refreshID = nil
    let generation = UUID()
    self.generation = generation
    loading = false
    connection = .connecting
    connectionTask = Task {
      var attempt = 0
      while !Task.isCancelled && foreground {
        do {
          let stream = try await client.events(
            cursor: storedPairing.flatMap { disk.cursors[$0.hostId] })
          guard generation == self.generation else { return }
          try await reconcile()
          guard generation == self.generation, !Task.isCancelled else { return }
          connection = .ready
          attempt = 0
          for try await frame in stream {
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            if let id = frame.id, let host { disk.cursors[host.hostId] = id }
            if frame.event == "heartbeat" { continue }
            if frame.event == "reset" {
              connection = .reconnecting
              try await reconcile()
              guard generation == self.generation, !Task.isCancelled else { return }
              connection = .ready
            } else {
              let hint = try? JSONDecoder().decode(EventHint.self, from: Data(frame.data.utf8))
              if hint?.workspaceId == nil || hint?.workspaceId == selectedWorkspace {
                scheduleRefresh()
              }
            }
          }
          throw RemoteError.unavailable
        } catch {
          if Task.isCancelled || generation != self.generation { return }
          let diagnostic = error as NSError
          Logger(subsystem: "com.saltypanda.openworkremote", category: "connection").error(
            "Connection failed: \(diagnostic.domain,privacy:.public) code \(diagnostic.code,privacy:.public)")
          if case RemoteError.unauthorized = error {
            connection = .revoked
            self.generation = UUID()
            refreshTask?.cancel()
            refreshTask = nil
            refreshID = nil
            directory = PagedSnapshot()
            history = PagedSnapshot()
            workspaces = []
            messages = []
            sessions = []
            approvals = []
            status = nil
            selectedSession = nil
            selectedWorkspace = nil
            stopRequested = false
            loading = false
            return
          }
          if case RemoteError.incompatible = error {
            connection = .incompatible
            return
          }
          connection = attempt > 2 ? .offline : .reconnecting
          let delay = min(30, 1 << min(attempt, 5))
          attempt += 1
          try? await Task.sleep(for: .milliseconds(delay * 1000 + Int.random(in: 0...350)))
        }
      }
    }
  }
  private func scheduleRefresh() {
    guard refreshTask == nil else { return }
    let id = UUID()
    let current = generation
    refreshID = id
    refreshTask = Task {
      defer { if refreshID == id { refreshTask = nil; refreshID = nil } }
      do {
        try await Task.sleep(for: .milliseconds(200))
        try Task.checkCancellation()
        guard current == generation, foreground else { return }
        try await reconcile()
      } catch {
        guard !Task.isCancelled, current == generation, foreground else { return }
        notice = "Updates paused. Reconnecting to your computer."
        connect()
      }
    }
  }
  func reconcile() async throws {
    guard let client else { throw RemoteError.unavailable }
    let current = generation
    let h = try await client.host()
    guard h.protocolVersion == 1, h.compatibility == "supported", h.hostId == storedPairing?.hostId
    else { throw RemoteError.incompatible }
    let w = try await client.workspaces().data
    guard current == generation else { return }
    host = h
    workspaces = w
    let previousWorkspace = selectedWorkspace
    if selectedWorkspace == nil, let saved = disk.conversation.selected, saved.hostId == h.hostId,
      w.contains(where: { $0.id == saved.workspaceId })
    {
      selectedWorkspace = saved.workspaceId
    } else if selectedWorkspace == nil || !w.contains(where: { $0.id == selectedWorkspace }) {
      selectedWorkspace = w.first?.id
    }
    if previousWorkspace != selectedWorkspace {
      directory = PagedSnapshot()
      history = PagedSnapshot()
      sessions = []
      messages = []
      approvals = []
      status = nil
      selectedSession = nil
      if let previousWorkspace, previousWorkspace != selectedWorkspace {
        disk.conversation.deselect()
      }
    }
    guard let wid = selectedWorkspace else {
      sessions = []
      messages = []
      approvals = []
      status = nil
      selectedSession = nil
      return
    }
    let page = try await client.sessions(wid)
    guard current == generation, selectedWorkspace == wid else { return }
    directory.latest(page.data, cursor: page.cursor)
    sessions = directory.rows.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    let sid =
      selectedSession?.workspaceId == wid
      ? selectedSession?.id
      : disk.conversation.selected.flatMap {
        $0.hostId == h.hostId && $0.workspaceId == wid ? $0.sessionId : nil
      }
    if let sid {
      let session: ChatSession
      if let listed = sessions.first(where: { $0.id == sid }) {
        session = listed
      } else {
        do { session = try await client.session(wid, sid) } catch RemoteError.notFound {
          guard current == generation, selectedWorkspace == wid else { return }
          selectedSession = nil
          disk.conversation.deselect()
          history = PagedSnapshot()
          messages = []
          approvals = []
          status = nil
          notice = "This chat is no longer available. Its draft is kept on this iPhone."
          saveDrafts()
          return
        }
      }
      guard current == generation, selectedWorkspace == wid else { return }
      selectedSession = session
      disk.conversation.select(DraftKey(hostId: h.hostId, workspaceId: wid, sessionId: sid))
      try await loadSelected()
    } else {
      selectedSession = nil
      messages = []
      status = nil
      approvals = []
    }
  }
  func select(_ session: ChatSession) async {
    guard let host else { return }
    let current = generation
    let selection = UUID()
    selectionID = selection
    saveDrafts()
    selectedWorkspace = session.workspaceId
    selectedSession = session
    disk.conversation.select(
      DraftKey(hostId: host.hostId, workspaceId: session.workspaceId, sessionId: session.id))
    messages = []
    history = PagedSnapshot()
    status = nil
    approvals = []
    stopRequested = false
    notice = nil
    loading = true
    defer { if current == generation, selection == selectionID { loading = false } }
    do { try await loadSelected() } catch {
      guard current == generation, selection == selectionID else { return }
      notice = "This chat could not be loaded. Reconnect and try again."
    }
    guard current == generation, selection == selectionID else { return }
    saveDrafts()
  }
  func loadSelected() async throws {
    guard let client, let selectedSession else { return }
    let session = selectedSession
    let current = generation
    let selection = selectionID
    async let m = client.messages(session.workspaceId, session.id)
    async let s = client.status(session.workspaceId, session.id)
    async let a = client.approvals(session.workspaceId, session.id)
    let snapshot: (Envelope<[ChatMessage]>, SessionStatus, [Approval])
    do { snapshot = try await (m, s, a) } catch RemoteError.notFound {
      guard current == generation, selection == selectionID, self.selectedSession?.id == session.id,
        self.selectedWorkspace == session.workspaceId else { return }
      self.selectedSession = nil
      disk.conversation.deselect()
      history = PagedSnapshot()
      messages = []; approvals = []; status = nil
      notice = "This chat is no longer available. Its draft is kept on this iPhone."
      saveDrafts()
      return
    }
    let (page, state, pending) = snapshot
    guard current == generation, selection == selectionID, self.selectedSession?.id == session.id,
      self.selectedSession?.workspaceId == session.workspaceId
    else { return }
    InteractionMetrics.measure("Apply chat snapshot") {
      history.latest(page.data, cursor: page.cursor)
      messages = history.rows.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
      status = state
      approvals = pending
      if ["idle", "error"].contains(state.phase) { stopRequested = false }
    }
  }
  func changeWorkspace(_ workspace: Workspace) async {
    selectionID = UUID()
    loading = false
    saveDrafts()
    selectedWorkspace = workspace.id
    selectedSession = nil
    disk.conversation.deselect()
    directory = PagedSnapshot()
    history = PagedSnapshot()
    messages = []
    status = nil
    approvals = []
    stopRequested = false
    do { try await reconcile() } catch { notice = "Workspace unavailable." }
  }
  func rename(_ session: ChatSession, title: String, requestId: UUID) async throws {
    guard connection == .ready, host?.capabilities.renameSession == true, let client else {
      throw RemoteError.unavailable
    }
    let current = generation
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    var failure: (any Error)?
    do {
      let receipt = try await client.rename(session.workspaceId, session.id, title: title,
        previousTitle: session.title, requestId: requestId)
      if !["accepted", "confirmed"].contains(receipt.state) { failure = RemoteError.outcomeUnknown }
    } catch { failure = error }
    guard current == generation else { throw RemoteError.cancelled }
    // Read back even after a lost response. Never repeat the mutation to check its outcome.
    let actual = try await client.session(session.workspaceId, session.id)
    guard current == generation, actual.id == session.id, actual.workspaceId == session.workspaceId else {
      throw RemoteError.cancelled
    }
    if selectedWorkspace == actual.workspaceId {
      directory.latest([actual], cursor: directory.cursor)
      sessions = directory.rows.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
      if selectedSession?.id == actual.id { selectedSession = actual }
    }
    guard actual.title == title else { throw failure ?? RemoteError.conflict }
  }
  func olderSessions() async {
    guard let client, let wid = selectedWorkspace, let cursor = sessionCursor else { return }
    let current = generation
    do {
      let page = try await client.sessions(wid, cursor: cursor)
      guard current == generation, wid == selectedWorkspace else { return }
      directory.older(page.data, cursor: page.cursor)
      sessions = directory.rows.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    } catch { notice = "Older chats could not be loaded." }
  }
  func earlierMessages() async {
    guard let client, let s = selectedSession, let cursor = messageCursor else { return }
    let current = generation
    do {
      let page = try await client.messages(s.workspaceId, s.id, cursor: cursor)
      guard current == generation, selectedSession?.id == s.id, selectedWorkspace == s.workspaceId else { return }
      history.older(page.data, cursor: page.cursor)
      messages = history.rows.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    } catch { notice = "Earlier replies could not be loaded." }
  }
  private func persist() async throws {
    guard let draftStore else { throw RemoteError.unavailable }
    saveRevision += 1
    try await draftStore.save(disk, revision: saveRevision)
  }
  var hasPairing: Bool { storedPairing != nil }
  var creationKey: MutationKey? {
    guard let host, let wid = selectedWorkspace else { return nil }
    return MutationKey(hostId: host.hostId, workspaceId: wid, sessionId: nil, action: .create)
  }
  var uncertainCreation: Bool { creationKey.map { disk.mutations.requiresReview($0) } ?? false }
  func send() async {
    guard canSend, let client else { return }
    let current = generation
    do {
      let intent = try disk.conversation.beginSend(ready: canSend)
      sending = true
      defer {
        sending = false
        saveDrafts()
      }
      // Persist admission intent before the network request can leave the phone.
      do { try await persist() } catch {
        disk.conversation.applyReceipt(intent, accepted: false)
        notice = "Your request could not be saved. No message was sent."
        return
      }
      guard current == generation else {
        disk.conversation.applyReceipt(intent, accepted: false)
        return
      }
      do {
        let r = try await client.send(intent)
        let accepted =
          ["accepted", "confirmed"].contains(r.state)
          && r.requestId == intent.requestId.uuidString.lowercased()
          && r.resourceId == intent.key.sessionId
        disk.conversation.applyReceipt(intent, accepted: accepted)
        if !accepted {
          notice = "Delivery is uncertain. Check the conversation before trying again."
        }
      } catch {
        disk.conversation.applyReceipt(intent, accepted: false)
        notice = "Delivery is uncertain. Check the conversation before trying again."
      }
      saveDrafts()
      guard current == generation else { return }
      do { try await loadSelected() } catch { connect() }
    } catch { notice = "Your message could not be sent. Check the connection and message length." }
  }
  func stop() async {
    guard connection == .ready, !stopRequested, let client, let s = selectedSession, let host,
      host.capabilities.stop
    else { return }
    let current = generation
    let key = MutationKey(
      hostId: host.hostId, workspaceId: s.workspaceId, sessionId: s.id, action: .stop)
    do {
      let id = try disk.mutations.begin(key)
      stopRequested = true
      do { try await persist() } catch {
        disk.mutations.finish(key, accepted: true)
        stopRequested = false
        notice = "Your request could not be saved. Stop was not sent."
        return
      }
      guard current == generation else {
        disk.mutations.finish(key, accepted: true)
        return
      }
      do {
        let r = try await client.stop(s.workspaceId, s.id, requestId: id)
        let accepted =
          r.state == "accepted" && r.requestId == id.uuidString.lowercased() && r.resourceId == s.id
        disk.mutations.finish(key, accepted: accepted)
        if !accepted { notice = "Stop is unconfirmed. Check the conversation." }
      } catch {
        disk.mutations.finish(key, accepted: false)
        notice = "Stop could not be confirmed. Check your computer."
      }
      saveDrafts()
      guard current == generation else { return }
      try await loadSelected()
    } catch { notice = "Check the conversation before requesting Stop again." }
  }
  func checkConversation() async {
    guard let key = disk.conversation.selected else { return }
    do {
      try await loadSelected()
      guard key == disk.conversation.selected else { return }
      disk.conversation.checkedConversation(key)
      let stop = MutationKey(
        hostId: key.hostId, workspaceId: key.workspaceId, sessionId: key.sessionId, action: .stop)
      disk.mutations.reviewed(stop)
      stopRequested = false
      saveDrafts()
      notice = "Review the conversation before sending the retained draft again."
    } catch { notice = "Your computer is unavailable. Keep the draft and check later." }
  }
  func reviewRecentChats() async {
    guard let key = creationKey else { return }
    do {
      try await reconcile()
      guard key == creationKey else { return }
      disk.mutations.reviewed(key)
      saveDrafts()
      notice = "Review recent chats before creating another."
    } catch { notice = "Recent chats could not be checked. Reconnect and try again." }
  }
  func createChat() async {
    guard let client, let wid = selectedWorkspace, connection == .ready,
      host?.capabilities.createSession == true, !loading, let key = creationKey, !uncertainCreation
    else { return }
    let current = generation
    loading = true
    defer {
      loading = false
      saveDrafts()
    }
    do {
      let id = try disk.mutations.begin(key)
      do { try await persist() } catch {
        disk.mutations.finish(key, accepted: true)
        notice = "Your request could not be saved. No chat was created."
        return
      }
      guard current == generation else {
        disk.mutations.finish(key, accepted: true)
        return
      }
      let r: MutationReceipt
      do { r = try await client.create(wid, requestId: id) } catch {
        disk.mutations.finish(key, accepted: false)
        notice = "New chat creation is uncertain. Check recent chats before trying again."
        return
      }
      guard r.state == "accepted", r.requestId == id.uuidString.lowercased(), let sid = r.resourceId
      else {
        disk.mutations.finish(key, accepted: false)
        notice = "New chat creation is uncertain. Check recent chats before trying again."
        return
      }
      disk.mutations.finish(key, accepted: true)
      saveDrafts()
      guard current == generation, creationKey == key else { return }
      let session = try await client.session(wid, sid)
      guard current == generation, creationKey == key else { return }
      await select(session)
      try await reconcile()
    } catch {
      notice = "The chat was created, but could not be loaded. Reconnect and check recent chats."
    }
  }
  func approvalKey(_ approval: Approval) -> MutationKey? {
    guard let host, let session = selectedSession, session.id == approval.sessionId else { return nil }
    return MutationKey(hostId: host.hostId, workspaceId: session.workspaceId, sessionId: session.id,
      action: .approval, approvalId: approval.id, revision: approval.revision)
  }
  func approvalNeedsReview(_ approval: Approval) -> Bool {
    approvalKey(approval).map { disk.mutations.requiresReview($0) } ?? true
  }
  func replyApproval(_ approval: Approval, decision: String) async {
    guard connection == .ready, host?.capabilities.replyApproval == true, let client,
      let key = approvalKey(approval), !disk.mutations.requiresReview(key),
      let current = approvals.first(where: { $0.id == approval.id }),
      current.revision == approval.revision, current.supportedDecisions.contains(decision) else {
      notice = "This approval has changed. Review the latest request before answering."
      return
    }
    let currentGeneration = generation
    do {
      let id = try disk.mutations.begin(key)
      do { try await persist() } catch {
        disk.mutations.finish(key, accepted: true)
        notice = "Your request could not be saved. No answer was sent."
        return
      }
      guard currentGeneration == generation else {
        disk.mutations.finish(key, accepted: true)
        return
      }
      do {
        let receipt = try await client.replyApproval(key.workspaceId, approval.sessionId,
          approval: approval, decision: decision, requestId: id)
        let accepted = receipt.state == "accepted" && receipt.requestId == id.uuidString.lowercased()
          && receipt.resourceId == approval.id
        disk.mutations.finish(key, accepted: accepted)
        if currentGeneration == generation && !accepted {
          notice = "The answer is unconfirmed. Check the approval before answering again."
        }
      } catch RemoteError.conflict {
        disk.mutations.finish(key, accepted: true)
        if currentGeneration == generation { notice = "This approval changed. Review the latest request." }
      } catch {
        disk.mutations.finish(key, accepted: false)
        if currentGeneration == generation { notice = "The answer is unconfirmed. Check your computer." }
      }
      saveDrafts()
      guard currentGeneration == generation else { return }
      try await loadSelected()
    } catch { notice = "The approval could not be checked. Reconnect and try again." }
  }
  func checkApproval(_ approval: Approval) async {
    guard let key = approvalKey(approval) else { return }
    do {
      try await loadSelected()
      guard key == approvalKey(approval) else { return }
      disk.mutations.reviewed(key)
      saveDrafts()
      notice = "Review the latest approval before answering again."
    } catch { notice = "The approval could not be checked. Reconnect and try again." }
  }
  func pair(_ text: String) {
    cancelPairing()
    pairingTask?.cancel()
    let current = UUID()
    pairingGeneration = current
    pairingError = nil
    do {
      let payload = try PairingPayload.decode(text)
      pendingPhone = true
      connection = .pairing
      pairingTask = Task {
        do {
          let pending = try BridgeClient(origin: PairingValidation.origin(payload.origin), transport: transport)
          let claim = try await pending.claim(
            payload, deviceId: UUID().uuidString, deviceName: "My iPhone")
          try Task.checkCancellation()
          guard current == pairingGeneration else { return }
          while !Task.isCancelled {
            try await Task.sleep(for: .seconds(2))
            let response = try await pending.poll(claim)
            try Task.checkCancellation()
            guard current == pairingGeneration else { return }
            switch response.state {
            case "pending": continue
            case "approved":
              guard let token = response.credential, let h = response.host, h.protocolVersion == 1,
                h.compatibility == "supported"
              else { throw RemoteError.incompatible }
              let paired = try BridgeClient(
                origin: PairingValidation.origin(payload.origin), token: token, transport: transport)
              let connection = StoredPairing(origin: payload.origin, token: token, hostId: h.hostId)
              try pairingPersistence.save(connection)
              savedPendingPairing = true
              try await paired.ack()
              try Task.checkCancellation()
              guard current == pairingGeneration else { return }
              let workspaces = try await paired.workspaces()
              try Task.checkCancellation()
              guard current == pairingGeneration else { return }
              guard !workspaces.data.isEmpty else { throw RemoteError.forbidden }
              savedPendingPairing = false
              storedPairing = connection
              client = paired
              host = h
              self.workspaces = workspaces.data
              pendingPhone = false
              onboardingStep = 4
              connect()
              return
            case "expired": throw RemoteError.invalidPairing
            case "denied":
              pairingError = "The connection wasn’t approved. Start again on your computer."
              pendingPhone = false
              self.connection = .unpaired
              return
            default: throw RemoteError.invalidResponse
            }
          }
        } catch {
          if Task.isCancelled || current != pairingGeneration { return }
          if savedPendingPairing && storedPairing == nil {
            do { try pairingPersistence.remove(); savedPendingPairing = false } catch {
              notice = "Pairing could not finish or be removed. Unlock this iPhone and try again."
            }
          }
          let diagnostic = error as NSError
          Logger(subsystem: "com.saltypanda.openworkremote", category: "connection").error(
            "Pairing failed: \(diagnostic.domain,privacy:.public) code \(diagnostic.code,privacy:.public)"
          )
          pairingError =
            error is RemoteError
            ? "Pairing could not finish. Create a new code on your computer and check Tailscale."
            : "Your computer could not be reached. Check Tailscale and try again."
          pendingPhone = false
          connection = .unpaired
        }
      }
    } catch {
      pairingError = "That pairing code is invalid. Create a new code on your computer."
      pendingPhone = false
    }
  }
  func cancelPairing() {
    pairingTask?.cancel()
    pairingGeneration = UUID()
    if savedPendingPairing && storedPairing == nil {
      do { try pairingPersistence.remove(); savedPendingPairing = false } catch {
        notice = "The unfinished pairing could not be removed. Unlock this iPhone and try again."
      }
    }
    pendingPhone = false
    pairingError = nil
    if storedPairing == nil { connection = .unpaired }
  }
  func forget() async {
    saveDrafts()
    do { try pairingPersistence.remove() } catch {
      notice = "Pairing could not be removed from Keychain. Unlock this iPhone and try again."
      return
    }
    let previousClient = client
    clearLocalPairing()
    let current = generation
    onboardingStep = 0
    if let previousClient {
      do { try await previousClient.revoke() } catch {
        guard current == generation else { return }
        notice = "Local pairing removed. Revoke this phone on your computer when it is online."
      }
    }
  }
  private func pairAgain() {
    guard connection == .revoked else { return }
    do { try pairingPersistence.remove() } catch {
      notice = "Pairing could not be removed from Keychain. Unlock this iPhone and try again."
      return
    }
    clearLocalPairing()
    onboardingStep = 2
  }
  private func clearLocalPairing() {
    connectionTask?.cancel()
    pairingTask?.cancel()
    refreshTask?.cancel()
    refreshTask = nil
    refreshID = nil
    generation = UUID()
    pairingGeneration = UUID()
    client = nil
    storedPairing = nil
    host = nil
    directory = PagedSnapshot()
    history = PagedSnapshot()
    workspaces = []
    sessions = []
    messages = []
    approvals = []
    selectedSession = nil
    selectedWorkspace = nil
    status = nil
    stopRequested = false
    sending = false
    updatingControls = false
    loading = false
    notice = nil
    pairingError = nil
    pendingPhone = false
    savedPendingPairing = false
    disk.conversation.deselect()
    saveDrafts()
    connection = .unpaired
  }
  func sceneActive(_ active: Bool) {
    foreground = active
    if active {
      if client != nil && connection != .revoked { connect() }
    } else {
      saveDrafts()
      connectionTask?.cancel()
      refreshTask?.cancel()
      refreshTask = nil
      refreshID = nil
      generation = UUID()
      if connection != .revoked { connection = client == nil ? .unpaired : .connecting }
    }
  }
}

extension AppModel {
  var controlsScope: String {
    [host?.hostId ?? "", selectedWorkspace ?? "", selectedSession?.id ?? ""].joined(separator: "/")
  }
  var canEditControls: Bool {
    connection == .ready && !sending && !updatingControls && !loading && selectedSession != nil
      && ["idle", "error"].contains(status?.phase ?? "")
  }
  private func checkControlsScope(_ scope: String, _ revision: UUID) throws {
    guard scope == controlsScope, revision == generation else { throw RemoteError.cancelled }
  }
  func loadModelSettings() async throws -> ModelSettings {
    guard let client, let wid = selectedWorkspace, let sid = selectedSession?.id else { throw RemoteError.unavailable }
    let scope = controlsScope, revision = generation
    let value = try await client.modelSettings(wid, sid)
    try checkControlsScope(scope, revision)
    return value
  }
  func changeModel(_ selection: ModelSelection, revision: String) async throws {
    guard canEditControls, let client, let wid = selectedWorkspace, let sid = selectedSession?.id else { throw RemoteError.unavailable }
    let scope = controlsScope, epoch = generation
    updatingControls = true
    defer { updatingControls = false }
    let receipt = try await client.setModel(wid, sid, model: selection, revision: revision, requestId: UUID())
    try checkControlsScope(scope, epoch)
    guard receipt.state == "accepted" || receipt.state == "confirmed" else { throw RemoteError.outcomeUnknown }
    let actual = try await client.modelSettings(wid, sid)
    try checkControlsScope(scope, epoch)
    guard actual.current == selection else { throw RemoteError.conflict }
    try await reconcile()
  }
  func loadDeviceAccess() async throws -> DeviceAccess {
    guard let client else { throw RemoteError.unavailable }
    let scope = controlsScope, revision = generation
    let value = try await client.deviceAccess()
    try checkControlsScope(scope, revision)
    return value
  }
  func loadSavedPermissions() async throws -> SavedPermissions {
    guard let client, let wid = selectedWorkspace, let sid = selectedSession?.id else { throw RemoteError.unavailable }
    let scope = controlsScope, revision = generation
    let value = try await client.savedPermissions(wid, sid)
    try checkControlsScope(scope, revision)
    return value
  }
  func revokeSavedPermission(_ permission: SavedPermission) async throws {
    guard canEditControls, let client, let wid = selectedWorkspace, let sid = selectedSession?.id else { throw RemoteError.unavailable }
    let scope = controlsScope, epoch = generation
    updatingControls = true
    defer { updatingControls = false }
    let receipt = try await client.revokePermission(wid, sid, permission: permission, requestId: UUID())
    try checkControlsScope(scope, epoch)
    guard receipt.state == "accepted" || receipt.state == "confirmed" else { throw RemoteError.outcomeUnknown }
    let current = try await client.savedPermissions(wid, sid)
    try checkControlsScope(scope, epoch)
    guard !current.grants.contains(where: { $0.id == permission.id }) else { throw RemoteError.conflict }
  }
}
