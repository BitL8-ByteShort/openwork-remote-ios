import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@MainActor final class NativeSavedConnection {
  var value: StoredOpenCodeConnection?
  var saves = 0
  var failLoad = false, failSave = false, failRemove = false
  init(_ value: StoredOpenCodeConnection? = nil) { self.value = value }
  var persistence: OpenCodePersistence {
    OpenCodePersistence(load: { if self.failLoad { throw RemoteError.unavailable }; return self.value },
      save: { if self.failSave { throw RemoteError.unavailable }; self.value = $0; self.saves += 1 },
      remove: { if self.failRemove { throw RemoteError.unavailable }; self.value = nil })
  }
}
actor NativeConnectionTransport: HTTPTransport {
  var infoStatus = 200
  var pairingStatus = 200
  var reads = 0
  var version = "2.0.29"
  var holdPairing = false
  var resumePairing: CheckedContinuation<Void, Never>?
  func setInfoStatus(_ value: Int) { infoStatus = value }
  func setVersion(_ value: String) { version = value }
  func setPairingHeld() { holdPairing = true }
  func finishPairing() { resumePairing?.resume(); resumePairing = nil }
  func count() -> Int { reads }
  func data(for request: URLRequest) async throws -> (Data, Int) {
    reads += 1
    if request.url?.path.hasPrefix("/auth/connect/") == true {
      if holdPairing { await withCheckedContinuation { resumePairing = $0 } }
      return (Data(#"{"token":"native-new-token"}"#.utf8),pairingStatus)
    }
    return (Data("{\"version\":\"\(version)\",\"urls\":[],\"paths\":{\"tmp\":\"/tmp/native\"}}".utf8),infoStatus)
  }
  func events(for request: URLRequest) async throws -> AsyncThrowingStream<SSEFrame, any Error> { throw RemoteError.unavailable }
}
@MainActor func nativeStored(_ origin: String = "https://one.example") throws -> StoredOpenCodeConnection {
  StoredOpenCodeConnection(connection: try OpenCodeConnection(origin:URL(string:origin)!,displayName:"Test computer"),token:"native-existing-token")
}

@Suite @MainActor struct OpenCodeConnectionTests {
  @Test func verifiedPairingCommitsOneNewEnvelope() async throws {
    let saved = NativeSavedConnection(), transport = NativeConnectionTransport()
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    let payload = try OpenCodePairingPayload.parse("https://one.example/auth/connect/synthetic")
    await model.connect(payload,origin:payload.origins[0],displayName:"Computer")
    #expect(model.state == .ready)
    #expect(saved.saves == 1)
    #expect(saved.value?.token == "native-new-token")
    #expect(model.connection?.id == saved.value?.connection.id)
    #expect(await transport.count() == 2)
  }
  @Test func failedStorageKeepsPreviousCredentialAndConnection() async throws {
    let original = try nativeStored(), saved = NativeSavedConnection()
    saved.value = original
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:NativeConnectionTransport())
    await model.start()
    saved.failSave = true
    let payload = try OpenCodePairingPayload.parse("https://two.example/auth/connect/synthetic")
    await model.connect(payload,origin:payload.origins[0],displayName:"Other computer")
    #expect(saved.value?.connection.id == original.connection.id)
    #expect(saved.value?.token == original.token)
    #expect(model.connection?.id == original.connection.id)
    #expect(model.issue == .storageUnavailable)
    model.cancelPairing()
    #expect(model.state == .ready)
  }
  @Test func authenticationRejectionRequiresPairAgainAcrossForeground() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    await transport.setInfoStatus(401)
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    #expect(model.state == .authenticationRejected)
    await model.reconnect()
    await model.sceneActive(true)
    #expect(await transport.count() == 1)
    #expect(saved.value != nil)
    model.pairAgain()
    #expect(model.state == .pairing)
    #expect(saved.value != nil)
  }
  @Test func networkFailureRetainsCredentialAndCanReconnect() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    await transport.setInfoStatus(503)
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    #expect(model.state == .offline)
    #expect(saved.value != nil)
    await transport.setInfoStatus(200)
    await model.reconnect()
    #expect(model.state == .ready)
  }
  @Test func cancellationFencesALatePairingResponse() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    let oldID = model.connection?.id
    await transport.setPairingHeld()
    let payload = try OpenCodePairingPayload.parse("https://two.example/auth/connect/synthetic")
    let task = Task { await model.connect(payload,origin:payload.origins[0],displayName:"Other computer") }
    for _ in 0..<100 { if await transport.count() == 2 { break }; await Task.yield() }
    model.cancelPairing()
    await transport.finishPairing()
    await task.value
    #expect(model.connection?.id == oldID)
    #expect(saved.saves == 0)
    #expect(model.state == .ready)
  }
  @Test func sameOriginRepairKeepsIdentityOtherOriginGetsFreshIdentity() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    let oldID = model.connection?.id
    let same = try OpenCodePairingPayload.parse("https://one.example/auth/connect/synthetic")
    await model.connect(same,origin:same.origins[0],displayName:"Computer")
    #expect(model.connection?.id == oldID)
    let other = try OpenCodePairingPayload.parse("https://two.example/auth/connect/synthetic")
    await model.connect(other,origin:other.origins[0],displayName:"Other")
    #expect(model.connection?.id != oldID)
  }
  @Test func keychainDeniedDoesNotLookLikeANewInstall() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    saved.failLoad = true
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    #expect(model.state == .storageUnavailable)
    #expect(await transport.count() == 0)
    #expect(saved.value != nil)
  }
  @Test func failedForgetPreservesActiveConnection() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    saved.failRemove = true
    model.forgetLocalConnection()
    #expect(model.connection != nil)
    #expect(saved.value != nil)
    #expect(model.issue == .storageUnavailable)
    saved.failRemove = false
    model.forgetLocalConnection()
    #expect(model.connection == nil)
    #expect(saved.value == nil)
    #expect(model.state == .unpaired)
    #expect(await transport.count() == 1)
  }
  @Test func unqualifiedServerCannotReplaceWorkingConnection() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    let oldID = model.connection?.id
    await transport.setVersion("9.0.0")
    let payload = try OpenCodePairingPayload.parse("https://two.example/auth/connect/synthetic")
    await model.connect(payload,origin:payload.origins[0],displayName:"Other")
    #expect(model.connection?.id == oldID)
    #expect(saved.saves == 0)
    #expect(model.issue == .incompatible)
  }
  @Test func backgroundDuringRedemptionLeavesAnActionableFreshCodeState() async throws {
    let saved = NativeSavedConnection(try nativeStored()), transport = NativeConnectionTransport()
    let model = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    await model.start()
    let oldID = model.connection?.id
    await transport.setPairingHeld()
    let payload = try OpenCodePairingPayload.parse("https://two.example/auth/connect/synthetic")
    let task = Task { await model.connect(payload,origin:payload.origins[0],displayName:"Other") }
    for _ in 0..<100 { if await transport.count() == 2 { break }; await Task.yield() }
    await model.sceneActive(false)
    #expect(model.issue == .pairingOutcomeUnknown)
    await model.sceneActive(true)
    await transport.finishPairing(); await task.value
    #expect(model.connection?.id == oldID)
    #expect(saved.saves == 0)
    #expect(model.issue == .pairingOutcomeUnknown)
    model.cancelPairing()
    #expect(model.state == .ready)
  }
}
