import Foundation
import Observation
import OpenWorkRemoteCore

enum NativeConnectionState:Equatable { case unpaired, pairing, connecting, ready, offline, authenticationRejected, incompatible, storageUnavailable }
enum NativeConnectionIssue { case freshPairingCodeRequired, pairingOutcomeUnknown, networkUnavailable, storageUnavailable, incompatible, serverPasswordRejected, passwordConnectionUnconfirmed }
@MainActor @Observable final class ConnectionCoordinator {
  private(set) var state: NativeConnectionState = .unpaired{didSet{if state != oldValue{changeObserver?()}}}
  private(set) var issue: NativeConnectionIssue?
  private(set) var connection: OpenCodeConnection?
  private(set) var client: OpenCodeClient?{didSet{if client !== oldValue{changeObserver?()}}}
  private(set) var isBusy = false
  private(set) var serverVersion:String?
  @ObservationIgnored private let persistence: OpenCodePersistence
  @ObservationIgnored private let transport: any HTTPTransport
  @ObservationIgnored private var saved: StoredOpenCodeConnection?
  @ObservationIgnored private var generation: UInt64 = 0
  @ObservationIgnored private var resumeState: NativeConnectionState = .unpaired
  @ObservationIgnored private var changeObserver:(@MainActor ()->Void)?
  @ObservationIgnored private var passwordRequest:Task<OpenCodePairingPayload,any Error>?
  func observeChanges(_ handler:@escaping @MainActor ()->Void){changeObserver=handler}

  init(persistence: OpenCodePersistence = .keychain,
       transport: any HTTPTransport = SessionTransport(profile: .openCode)) {
    self.persistence = persistence; self.transport = transport
  }
  func start() async {
    do {
      saved = try persistence.load(); connection = saved?.connection
      guard saved != nil else { state = .unpaired; resumeState = state; return }
    } catch {
      state = .storageUnavailable; issue = .storageUnavailable; resumeState = state; return
    }
    await reconnect()
  }
  func connect(_ payload: OpenCodePairingPayload, origin: URL, displayName: String) async {
    cancelPasswordRequest()
    generation &+= 1; let current = generation
    state = .pairing; issue = nil; isBusy = true
    defer { if generation == current { isBusy = false } }
    var receivedToken = false
    do {
      let pairing = try await OpenCodePairingClient(transport: transport).redeem(payload, origin: origin)
      receivedToken = true
      guard generation == current else { return }
      try Task.checkCancellation()
      // A re-pair at the same origin preserves local chat identities. Replacing a
      // computer gets a new namespace even if both servers use equal session IDs.
      let id = saved?.connection.origin == pairing.origin ? saved!.connection.id : ConnectionID()
      let candidate = try OpenCodeConnection(id: id, origin: pairing.origin, displayName: displayName)
      let candidateClient = try OpenCodeClient(connection: candidate, token: pairing.token, transport: transport)
      defer{if self.client !== candidateClient{candidateClient.retire()}}
      let info = try await candidateClient.info()
      guard generation == current else { return }
      try Task.checkCancellation()
      guard OpenCodeCompatibility.evaluate(version: info.version) == .qualified else { throw RemoteError.incompatible }
      let envelope = StoredOpenCodeConnection(connection: candidate, token: pairing.token)
      do { try persistence.save(envelope) }
      catch { issue = .storageUnavailable; state = .storageUnavailable; return }
      saved = envelope; connection = candidate; install(candidateClient)
      serverVersion=info.version
      state = .ready; resumeState = .ready; issue = nil
    } catch {
      guard generation == current else { return }
      if error is CancellationError || (error as? URLError)?.code == .cancelled { cancelPairing(); return }
      if error as? RemoteError == .incompatible {
        state = .incompatible; issue = .incompatible
      } else {
        state = .pairing
        issue = error as? RemoteError == .unauthorized ? .freshPairingCodeRequired : .pairingOutcomeUnknown
        // After redemption, even a server-info failure needs a fresh pairing code.
        if receivedToken { issue = .pairingOutcomeUnknown }
      }
    }
  }
  func connectUsingServerPassword(origin:URL,password:String,displayName:String)async{
    cancelPasswordRequest()
    generation &+= 1;let current=generation
    state = .pairing;issue=nil;isBusy=true
    defer{if generation==current{passwordRequest=nil;isBusy=false}}
    do{
      try Task.checkCancellation()
      let pairing=OpenCodePairingClient(transport:transport)
      let request=Task{try await pairing.issueUsingServerPassword(origin:origin,password:password)}
      passwordRequest=request
      let payload=try await withTaskCancellationHandler{
        try await request.value
      }onCancel:{request.cancel()}
      guard generation==current else{return}
      try Task.checkCancellation()
      passwordRequest=nil
      // Reuse normal single-use redemption, info validation and atomic persistence.
      // The master password is never put into a saved connection or active client.
      await connect(payload,origin:origin,displayName:displayName)
    }catch{
      guard generation==current else{return}
      if error is CancellationError || (error as? URLError)?.code == .cancelled{cancelPairing();return}
      if error as? RemoteError == .incompatible{state = .incompatible;issue = .incompatible}
      else{state = .pairing;issue = error as? RemoteError == .unauthorized ? .serverPasswordRejected:.passwordConnectionUnconfirmed}
    }
  }
  private func cancelPasswordRequest(){passwordRequest?.cancel();passwordRequest=nil}
  func reconnect() async {
    cancelPasswordRequest()
    guard state != .authenticationRejected, let saved else { return }
    generation &+= 1; let current = generation
    client?.retire();client=nil
    state = .connecting; issue = nil; isBusy = true
    defer { if generation == current { isBusy = false } }
    do {
      let candidateClient = try OpenCodeClient(connection: saved.connection, token: saved.token, transport: transport)
      defer{if self.client !== candidateClient{candidateClient.retire()}}
      let info = try await candidateClient.info()
      guard generation == current else { return }
      try Task.checkCancellation()
      install(candidateClient);serverVersion=info.version
      state = OpenCodeCompatibility.evaluate(version: info.version) == .qualified ? .ready : .incompatible
      if state == .incompatible { issue = .incompatible }
      resumeState = state
    } catch {
      guard generation == current else { return }
      if error as? RemoteError == .unauthorized {
        state = .authenticationRejected; issue = .freshPairingCodeRequired; client = nil
      } else {
        state = .offline; issue = .networkUnavailable
      }
      resumeState = state
    }
  }
  private func install(_ candidate:OpenCodeClient){
    if client !== candidate{client?.retire()}
    client=candidate
    candidate.observeAuthenticationFailure{[weak self,weak candidate] in
      Task{@MainActor in
        guard let self,let candidate,self.client === candidate else{return}
        candidate.retire();self.client=nil
        if self.state == .pairing{
          // Do not interrupt a new redemption because the previous credential expired.
          self.resumeState = .authenticationRejected
        }else{
          self.generation &+= 1;self.state = .authenticationRejected;self.resumeState = .authenticationRejected
          self.issue = .freshPairingCodeRequired;self.isBusy=false
        }
      }
    }
  }
  func retireRequests(){cancelPasswordRequest();client?.retire();client=nil;generation &+= 1;isBusy=false}
  func pairAgain() {
    cancelPasswordRequest()
    generation &+= 1; state = .pairing; issue = nil; isBusy = false
  }
  func cancelPairing() {
    cancelPasswordRequest()
    generation &+= 1; state = resumeState; issue = nil; isBusy = false
  }
  func sceneActive(_ active: Bool) async {
    if !active {
      cancelPasswordRequest()
      generation &+= 1
      if state == .pairing && isBusy { issue = .pairingOutcomeUnknown }
      if state == .connecting { state = .offline; resumeState = state }
      isBusy = false
    } else if state == .offline || state == .ready { await reconnect() }
  }
  func forgetLocalConnection() {
    retireRequests()
    do { try persistence.remove() }
    catch { issue = .storageUnavailable;state = .storageUnavailable;resumeState=state;return }
    saved = nil; connection = nil;serverVersion=nil
    state = .unpaired; resumeState = state; issue = nil; isBusy = false
  }
}
