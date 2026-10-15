#if !DEBUG
import Foundation
import Observation
import OpenWorkRemoteCore

/// Shipping composition has one backend. Legacy stores below are opened only
/// for local recovery/erasure and never receive a client or an active context.
@MainActor @Observable final class AppModel {
  private let engine: NativeAppCoordinator
  var native: NativeAppCoordinator? { engine }
  private(set) var nativeMigration: ConnectionMigration?
  private let pairingPersistence: PairingPersistence
  private let draftStore: DraftStore?
  private let injectedStorageDirectory: URL
  private let legacy: LegacyLocalRecovery
  private var nativeSceneTask: Task<Void, Never>?
  private let clearPreferences: @MainActor () -> Void
  private(set) var isRetired = false
  private(set) var localStorageReady = false
  private(set) var localDataBusy = false
  private(set) var resetReplacement: DataResetReport?
  var lastResetReport: DataResetReport?
  private var disk = DiskState()

  init(native: NativeAppCoordinator, legacyDraftStore: DraftStore,
       pairingPersistence: PairingPersistence = .keychain,
       transport _: (any HTTPTransport)? = nil) {
    self.engine = native
    self.pairingPersistence = pairingPersistence
    self.draftStore = legacyDraftStore
    self.injectedStorageDirectory = legacyDraftStore.directory
    let directory = legacyDraftStore.directory
    legacy = LegacyLocalRecovery(directory: directory)
    clearPreferences = {
      for key in ["appearance", "compactToolActivity"] { UserDefaults.standard.removeObject(forKey: key) }
    }
  }
  var connection: ConnectionState { engine.connectionState }
  var workspaces: [Workspace] { engine.workspaces }
  var sessions: [ChatSession] { engine.sessions }
  var messages: [ChatMessage] { engine.messages }
  var selectedWorkspace: String? { engine.navigation.selectedProjectID }
  var selectedSession: ChatSession? { engine.selectedSession }
  var sessionCursor: String? { engine.navigation.sessionCursor }
  var messageCursor: String? { engine.navigation.olderCursor }
  var draft: String {
    get { engine.draft }
    set { if !isRetired { engine.setDraft(newValue) } }
  }
  var notice: String? {
    get { engine.notice }
    set { engine.notice = newValue }
  }
  var uncertain: Bool { engine.uncertain }
  var uncertainCreation: Bool { engine.creation.pending != nil }
  var sending: Bool { engine.preparingSend || engine.conversation.sending }
  var loading: Bool { engine.navigation.loadingMessages }
  var stopRequested: Bool { engine.conversation.stopping }
  var canSend: Bool { !isRetired && engine.canSend }
  var serviceName: String { "OpenCode" }
  var computerName: String { engine.connection.connection?.displayName ?? "Your computer" }
  var connectionLabel: String {
    switch engine.connection.state {
    case .unpaired: "Not connected"
    case .pairing: "Pair your computer"
    case .connecting: "Connecting…"
    case .ready: "Connected"
    case .offline: "Computer unavailable"
    case .authenticationRejected: "Pairing expired or rejected"
    case .incompatible: "OpenCode update needs qualification"
    case .storageUnavailable: "Unlock this device to restore the connection"
    }
  }
  var isRunning: Bool { engine.conversation.isActive }
  var canChooseModel: Bool { connection == .ready && engine.controls.context != nil }
  var canBrowseFiles: Bool { connection == .ready && engine.results.context != nil }
  var canCreateChat: Bool { !isRetired && engine.canCreateChat }
  var hasNewerReplies: Bool { engine.navigation.hasNewReplies }
  var selectedSkillIDs: [String] { engine.workspace.selectedSkills.map(\.id) }
  func followLatest(_ following: Bool) { engine.followLatest(following) }
  func jumpToLatest() { engine.jumpToLatest() }
  func select(_ session: ChatSession) async { if !isRetired { await engine.select(session) } }
  func earlierMessages() async { if !isRetired { await engine.olderMessages() } }
  func olderSessions() async { if !isRetired { await engine.navigation.loadMoreSessions() } }
  func send() async { if !isRetired { await engine.send() } }
  func stop() async { if !isRetired { await engine.stop() } }
  func checkConversation() async { if !isRetired { await engine.checkConversation() } }
  func createChat() async { if !isRetired { await engine.createChat() } }
  func connect() { if !isRetired { nativeSceneTask = Task { await engine.reconnect() } } }
  func forget() async { if !isRetired { engine.forget() } }
  func sceneActive(_ active: Bool) {
    guard !isRetired else { return }
    nativeSceneTask?.cancel()
    if !active { engine.deactivate() }
    nativeSceneTask = Task { await engine.sceneActive(active) }
  }
  func removeSelectedSkill(_ id: String) {
    guard !isRetired, !sending, !uncertain, let context = engine.workspace.context else { return }
    Task { do { try await engine.workspace.removeSkill(id, context: context) }
      catch { notice = "The selected skill could not be removed safely." } }
  }
  func start() async {
    guard !isRetired else { return }
    do { if let draftStore { nativeMigration = ConnectionMigration(legacy: try pairingPersistence.load(), disk: try await draftStore.load()) } }
    catch { notice = "Earlier OpenWork drafts remain on this device, but their recovery text could not be opened." }
    do { try await engine.start(); localStorageReady = engine.ready }
    catch { localStorageReady = false; notice = "Saved PocketWork data could not be opened. Unlock the device and retry." }
  }
  func clearLocalDrafts() async -> Bool {
    guard !isRetired, localStorageReady, !localDataBusy else { return false }
    localDataBusy = true; defer { localDataBusy = false }
    var failures = false
    do { try await engine.journal.clearUnsentDrafts() } catch { failures = true }
    do { try await engine.forms.clearUnsentDrafts() } catch { failures = true }
    do { if let draftStore { disk = try await draftStore.clearUnsentDrafts(); nativeMigration = nil } } catch { failures = true }
    if !(await legacy.clearUnsentDrafts()) { failures = true }
    if failures { notice = "Some drafts could not be cleared. Unlock this device and try again. Unconfirmed action details and selected files are kept." }
    else { nativeMigration = nil }
    return !failures
  }
  func clearSharingPermissions() async -> Bool {
    guard !isRetired, !localDataBusy, engine.ready else { return false }
    localDataBusy = true; defer { localDataBusy = false }
    nativeSceneTask?.cancel(); engine.stopLocalWork()
    do { try await engine.sharing.clearConsents(); nativeSceneTask = Task { await engine.reconnect() }; return true }
    catch { notice = "Sharing permissions could not be cleared. The connection is paused. Unlock this device and try again."; return false }
  }
  func clearDownloadedFiles() async -> Bool {
    guard !isRetired, !localDataBusy else { return false }
    localDataBusy = true; defer { localDataBusy = false }
    var success = true
    do { try await engine.clearDownloadedCopies() } catch { success = false }
    do { try await legacy.clearDownloadedCopies() } catch { success = false }
    if !success { notice = "Some downloaded copies could not be removed. Unlock this device and try again." }
    return success
  }
  func resetLocalData() async -> DataResetReport? {
    guard !isRetired, !localDataBusy else { return nil }
    return await resetNativeLocalData(engine)
  }
  private func resetNativeLocalData(_ native:NativeAppCoordinator)async->DataResetReport{
    localDataBusy=true;nativeSceneTask?.cancel();native.stopLocalWork()
    // If either credential cannot be removed, preserve files for recovery and
    // leave a retryable, stopped connection instead of claiming a full reset.
    var credentialFailures:[String]=[]
    do{try pairingPersistence.remove()}catch{credentialFailures.append("Earlier OpenWork credential")}
    native.connection.forgetLocalConnection()
    if native.connection.state != .unpaired{credentialFailures.append("OpenCode credential")}
    if !credentialFailures.isEmpty{
      let report=DataResetReport(localFailures:credentialFailures,hostRevocation:.nativeNotRevoked,credentialsRemoved:false)
      lastResetReport=report;notice=report.summary;localDataBusy=false;return report
    }
    isRetired=true;localStorageReady=false
    await legacy.retireWriters()
    var failures=await native.resetLocalFiles()
    do{try await draftStore?.invalidateAndRemove()}catch{failures.append("Earlier chat drafts and action records")}
    failures += await legacy.removeAll()
    clearPreferences()
    let report=DataResetReport(localFailures:failures,hostRevocation:.nativeNotRevoked)
    resetReplacement=report;return report
  }
  func freshAfterReset(_ report: DataResetReport) throws -> AppModel {
    guard isRetired else { throw RemoteError.invalidResponse }
    let fresh = AppModel(native: try engine.freshAfterReset(), legacyDraftStore: try DraftStore(directory: injectedStorageDirectory), pairingPersistence: pairingPersistence)
    fresh.lastResetReport = report
    return fresh
  }
}
#endif
