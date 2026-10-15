import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor NativeConversationService:OpenCodeConversationServing {
  enum Mode:Sendable{case normal,lostResponse,conflict,rejected}
  let mode:Mode
  var admitted:OpenCodePrompt?
  var sent=0
  var active=false
  var failInterrupt=false
  var continuation:AsyncThrowingStream<OpenCodeEvent,any Error>.Continuation?
  var messageText="Initial"
  var holdNext=false
  var held:CheckedContinuation<Void,Never>?
  var heldWaiters:[CheckedContinuation<Void,Never>]=[]
  init(_ mode:Mode = .normal){self.mode=mode}
  func session(id:String) async throws -> OpenCodeSession {
    try JSONDecoder().decode(OpenCodeSession.self,from:Data(#"{"id":"ses_owned","projectID":"project","location":{"directory":"/project"},"time":{"created":1,"updated":2}}"#.utf8))
  }
  func messages(sessionID:String,cursor:String?) async throws -> OpenCodeMessagePage {
    let text=messageText
    if holdNext {
      holdNext=false
      await withCheckedContinuation{c in held=c;heldWaiters.forEach{$0.resume()};heldWaiters=[]}
    }
    return try JSONDecoder().decode(OpenCodeMessagePage.self,from:JSONSerialization.data(withJSONObject:[
      "data":[["id":"msg_existing","type":"user","text":text,"time":["created":1]]],"cursor":[:]]))
  }
  func receipt(_ prompt:OpenCodePrompt,sessionID:String) throws -> OpenCodePromptAdmission {
    try JSONDecoder().decode(OpenCodePromptAdmission.self,from:JSONSerialization.data(withJSONObject:[
      "id":prompt.id,"sessionID":sessionID,"type":"user","payload":["text":prompt.text]]))
  }
  func send(target:OpenCodeTarget,input:OpenCodePrompt) async throws -> OpenCodePromptAdmission {
    sent+=1
    if mode == .rejected{throw RemoteError.forbidden}
    admitted=try mode == .conflict ? OpenCodePrompt(id:input.id,text:"Another admitted body") : input
    if mode == .lostResponse{throw RemoteError.outcomeUnknown}
    return try receipt(admitted!,sessionID:target.sessionID)
  }
  func inbox(target:OpenCodeTarget) async throws -> [OpenCodeInboxItem] {
    guard let admitted else{return []}
    return try JSONDecoder().decode([OpenCodeInboxItem].self,from:JSONSerialization.data(withJSONObject:[[
      "id":admitted.id,"sessionID":target.sessionID,"type":"user","payload":["text":admitted.text]]]))
  }
  func activeSessions() async throws -> Set<String>{active ? ["ses_owned"] : []}
  func interrupt(target:OpenCodeTarget) async throws -> Bool {
    if failInterrupt{throw RemoteError.outcomeUnknown};let result=active;active=false;return result
  }
  func events() async throws -> AsyncThrowingStream<OpenCodeEvent,any Error> {
    let pair=AsyncThrowingStream<OpenCodeEvent,any Error>.makeStream();continuation=pair.continuation;return pair.stream
  }
  func sendCount()->Int{sent}
  func setInterruptFailure(){active=true;failInterrupt=true}
  func holdNextMessage(){holdNext=true}
  func waitUntilHeld() async {if held != nil{return};await withCheckedContinuation{heldWaiters.append($0)}}
  func releaseMessage(){held?.resume();held=nil}
  func setMessage(_ value:String){messageText=value}
}
@Suite @MainActor struct OpenCodeConversationCoordinatorTests {
  func setup(_ mode:NativeConversationService.Mode = .normal) async throws -> (ConversationCoordinator,NativeConversationService,NativeConversationJournal,OpenCodeTarget) {
    let journal=NativeConversationJournal(persistence:MemoryNativeConversationFile())
    try await journal.restore()
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let service=NativeConversationService(mode),coordinator=ConversationCoordinator(journal:journal)
    await coordinator.activate(target:target,service:service)
    return (coordinator,service,journal,target)
  }
  @Test func lostResponseReconcilesInboxWithoutResending() async throws {
    let (coordinator,service,journal,target)=try await setup(.lostResponse)
    defer{coordinator.deactivate()}
    try await journal.saveDraft("Synthetic prompt",for:target)
    await coordinator.send()
    #expect(await service.sendCount()==1)
    #expect(journal.pending(for:target)==nil)
    #expect(journal.draft(for:target).isEmpty)
    #expect(coordinator.issue==nil)
  }
  @Test func conflictingAdmissionKeepsOriginalIntentAndDraft() async throws {
    let (coordinator,service,journal,target)=try await setup(.conflict)
    defer{coordinator.deactivate()}
    try await journal.saveDraft("Original prompt",for:target)
    await coordinator.send()
    #expect(await service.sendCount()==1)
    #expect(journal.pending(for:target)?.state == .conflicting)
    #expect(journal.draft(for:target)=="Original prompt")
    #expect(coordinator.issue == .conflictingSend)
  }
  @Test func definiteRejectionPreservesEditableDraft() async throws {
    let (coordinator,service,journal,target)=try await setup(.rejected)
    defer{coordinator.deactivate()}
    try await journal.saveDraft("Rejected prompt",for:target)
    await coordinator.send()
    #expect(journal.pending(for:target)==nil)
    #expect(journal.draft(for:target)=="Rejected prompt")
    #expect(coordinator.issue == .sendRejected)
    #expect(await service.sendCount()==1)
  }
  @Test func failedStopDoesNotSayExecutionStopped() async throws {
    let (coordinator,service,_,_)=try await setup()
    defer{coordinator.deactivate()}
    await service.setInterruptFailure();await coordinator.refresh()
    #expect(coordinator.isActive)
    await coordinator.interrupt()
    #expect(coordinator.isActive)
    #expect(coordinator.issue == .stopOutcomeUnknown)
  }
  @Test(.timeLimit(.minutes(1))) func staleSnapshotCannotReplaceAnotherConnectionsEqualChatID() async throws {
    let (coordinator,service,_,_)=try await setup()
    defer{coordinator.deactivate()}
    await service.holdNextMessage()
    let old=Task{await coordinator.refresh()}
    await service.waitUntilHeld()
    let replacement=NativeConversationService()
    await replacement.setMessage("Current computer")
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    await coordinator.activate(target:target,service:replacement)
    await service.releaseMessage();await old.value
    #expect(coordinator.latest.first?.text=="Current computer")
    #expect(coordinator.target?.connectionID==target.connectionID)
  }
  @Test(.timeLimit(.minutes(1))) func eventDuringSnapshotTriggersFreshReadBeforeLateOldReadCanApply() async throws {
    let (coordinator,service,_,_)=try await setup()
    defer{coordinator.deactivate()}
    await service.holdNextMessage()
    let old=Task{await coordinator.refresh()}
    await service.waitUntilHeld();await service.setMessage("After event")
    let event=try OpenCodeEvent.decode(SSEFrame(event:"message",id:nil,
      data:#"{"id":"evt_changed","type":"session.renamed","data":{"sessionID":"ses_owned"}}"#))
    coordinator.receive(event)
    let clock=ContinuousClock(),deadline=ContinuousClock.now.advanced(by:.seconds(3))
    while coordinator.latest.first?.text != "After event",clock.now<deadline{try await Task.sleep(for:.milliseconds(10))}
    let fresh=coordinator.latest.first?.text=="After event"
    await service.releaseMessage();await old.value
    #expect(fresh)
    #expect(coordinator.latest.first?.text=="After event")
  }
}
