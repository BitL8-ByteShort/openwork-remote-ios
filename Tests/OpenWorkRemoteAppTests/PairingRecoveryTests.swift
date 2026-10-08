import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@MainActor private final class SavedPairing {
  var value: StoredPairing? = StoredPairing(
    origin: "https://computer.example.test", token: "revoked-test-credential", hostId: "original-host")
  var removalFails = false
  var persistence: PairingPersistence {
    PairingPersistence(load: { self.value }, save: { self.value = $0 }, remove: {
      if self.removalFails { throw RemoteError.unavailable }
      self.value = nil
    })
  }
}

private actor RejectedConnection: HTTPTransport {
  let rejection: RemoteError
  private(set) var eventAttempts = 0
  init(_ rejection: RemoteError = .unauthorized) { self.rejection = rejection }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    throw rejection
  }
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error> {
    eventAttempts += 1
    throw rejection
  }
}

@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
  for _ in 0..<100 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(condition(), "Connection did not reach the expected state")
}

@Test @MainActor func revokedReconnectOpensFreshPairingAndPreservesDraftAndUncertainSend() async throws {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let saved = SavedPairing(), transport = RejectedConnection()
  let model = AppModel(pairingPersistence: saved.persistence, transport: transport,
                       draftStore: try DraftStore(directory: folder))
  await model.start()
  try await waitUntil { model.connection == .revoked }
  let key = DraftKey(hostId: "original-host", workspaceId: "project", sessionId: "chat")
  model.disk.conversation.select(key)
  model.disk.conversation.setDraft("Keep this unsent draft")
  let send = try model.disk.conversation.beginSend(ready: true)
  model.disk.conversation.applyReceipt(send, accepted: false)

  model.connect()

  #expect(model.connection == .unpaired)
  #expect(model.onboardingStep == 2)
  #expect(!model.hasPairing)
  #expect(model.host == nil)
  #expect(saved.value == nil)
  #expect(model.disk.conversation.selected == nil)
  #expect(model.disk.conversation.draft(for: key) == "Keep this unsent draft")
  #expect(model.disk.conversation.pendingRequestId(for: key) == send.requestId)
  #expect(model.disk.conversation.uncertain.contains(key))
  #expect(await transport.eventAttempts == 1)
  model.sceneActive(false)
}

@Test @MainActor func revokedPairingStaysRevokedAcrossBackgroundAndForeground() async throws {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let saved = SavedPairing(), transport = RejectedConnection()
  let model = AppModel(pairingPersistence: saved.persistence, transport: transport,
                       draftStore: try DraftStore(directory: folder))
  await model.start()
  try await waitUntil { model.connection == .revoked }
  model.sceneActive(false)
  #expect(model.connection == .revoked)
  model.sceneActive(true)
  #expect(model.connection == .revoked)
  #expect(await transport.eventAttempts == 1)
  model.sceneActive(false)
}

@Test @MainActor func failedCredentialRemovalKeepsRevokedStateAndDoesNotPair() async throws {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let saved = SavedPairing(), transport = RejectedConnection()
  saved.removalFails = true
  let model = AppModel(pairingPersistence: saved.persistence, transport: transport,
                       draftStore: try DraftStore(directory: folder))
  await model.start()
  try await waitUntil { model.connection == .revoked }
  model.connect()
  #expect(model.connection == .revoked)
  #expect(model.hasPairing)
  #expect(saved.value != nil)
  #expect(model.onboardingStep != 2)
  #expect(model.notice != nil)
  model.sceneActive(false)
}

@Test @MainActor func networkFailureKeepsPairingForOrdinaryReconnect() async throws {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let saved = SavedPairing(), transport = RejectedConnection(.unavailable)
  let model = AppModel(pairingPersistence: saved.persistence, transport: transport,
                       draftStore: try DraftStore(directory: folder))
  await model.start()
  try await waitUntil { model.connection == .reconnecting }
  model.connect()
  #expect(model.hasPairing)
  #expect(saved.value != nil)
  #expect(model.onboardingStep != 2)
  model.sceneActive(false)
}
