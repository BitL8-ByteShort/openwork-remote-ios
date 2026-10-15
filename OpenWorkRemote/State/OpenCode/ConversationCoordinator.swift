import Foundation
import Observation
import OpenWorkRemoteCore

enum NativeConversationIssue {case unavailable,locationChanged,unknownSend,conflictingSend,sendRejected,storage,stopOutcomeUnknown,authenticationRequired,incompatible}
enum NativeStreamState {case stopped,connecting,live,polling}
@MainActor @Observable final class ConversationCoordinator {
  let journal:NativeConversationJournal
  private(set) var target:OpenCodeTarget?
  private(set) var latest:[OpenCodeMessage]=[]
  private(set) var isActive=false
  private var sendingTargets=Set<OpenCodeTarget>()
  var sending:Bool{target.map{sendingTargets.contains($0)} ?? false}
  private(set) var currentSession:OpenCodeSession?
  private(set) var stopping=false
  private(set) var loading=false
  private(set) var issue:NativeConversationIssue?
  private(set) var streamState:NativeStreamState = .stopped
  private(set) var liveText=NativeLiveTextBuffer()
  @ObservationIgnored private var service:(any OpenCodeConversationServing)?
  @ObservationIgnored private var generation=UUID()
  @ObservationIgnored private var mutationEpoch=UUID()
  @ObservationIgnored private var mutationService:ObjectIdentifier?
  @ObservationIgnored private var snapshotSequence:UInt64=0
  @ObservationIgnored private var consumer:Task<Void,Never>?
  @ObservationIgnored private var recovery:Task<Void,Never>?
  @ObservationIgnored private var refreshTask:Task<Void,Never>?
  @ObservationIgnored private var snapshotSink:((OpenCodeTarget,OpenCodeSession,OpenCodeMessagePage)->Void)?
  @ObservationIgnored private var eventSink:((OpenCodeEvent)->Void)?
  @ObservationIgnored private var resyncSink:(()->Void)?
  func observe(snapshot:@escaping(OpenCodeTarget,OpenCodeSession,OpenCodeMessagePage)->Void,event:@escaping(OpenCodeEvent)->Void,resync:@escaping()->Void){
    snapshotSink=snapshot;eventSink=event;resyncSink=resync
  }
  @ObservationIgnored private var dirty=false
  @ObservationIgnored private var seenEvents:[String]=[]
  init(journal:NativeConversationJournal){self.journal=journal}
  func activate(target:OpenCodeTarget,service:any OpenCodeConversationServing) async {
    clearSelection()
    let identity=ObjectIdentifier(service)
    if mutationService != identity{mutationEpoch=UUID();mutationService=identity}
    self.target=target;self.service=service
    let current=generation
    await subscribe(current:current,attempt:0)
    guard current==generation else{return}
    await refresh()
  }
  func deactivate(){mutationEpoch=UUID();mutationService=nil;clearSelection()}
  /// Navigation can stop old reads without abandoning an authorized, captured send.
  func clearSelection() {
    generation=UUID();consumer?.cancel();recovery?.cancel();refreshTask?.cancel()
    consumer=nil;recovery=nil;refreshTask=nil;service=nil;target=nil;latest=[];seenEvents=[]
    dirty=false;isActive=false;currentSession=nil;stopping=false;loading=false;issue=nil;streamState = .stopped;liveText.reset()
  }
  func refresh() async {
    guard let service,let target else{return}
    let current=generation;snapshotSequence &+= 1;let sequence=snapshotSequence
    loading=true
    defer{if current==generation,sequence==snapshotSequence{loading=false}}
    do {
      async let session=service.session(id:target.sessionID)
      async let messages=service.messages(sessionID:target.sessionID,cursor:nil)
      async let inbox=service.inbox(target:target)
      async let active=service.activeSessions()
      let (actual,page,queued,running)=try await (session,messages,inbox,active)
      guard current==generation,sequence==snapshotSequence,!Task.isCancelled else{return}
      guard OpenCodeIdentity.matches(actual.id,target.sessionID),actual.projectID==target.projectID,OpenCodeIdentity.matches(actual.location.directory,target.directory),actual.time.archived==nil else{
        issue = .locationChanged;return
      }
      currentSession=actual;snapshotSink?(target,actual,page);latest=page.data;liveText.confirmed(by:page.data);isActive=running.contains(target.sessionID)
      if issue == .unavailable{issue=nil}
      try await reconcile(target:target,page:page,inbox:queued,service:service,current:current)
    }catch{
      guard current==generation,sequence==snapshotSequence else{return}
      if error as? RemoteError == .unauthorized{issue = .authenticationRequired;consumer?.cancel();recovery?.cancel()}
      else if error is CancellationError{return}
      else if journal.storageIssue{issue = .storage}
      else{issue = .unavailable}
    }
  }
  func send(files:[OpenCodePromptFile]=[],skills:[String]=[]) async {
    guard let target,let service,!sendingTargets.contains(target),journal.ready,!journal.storageIssue,journal.pending(for:target)==nil,
      issue != .locationChanged,issue != .authenticationRequired else{return}
    let current=generation,epoch=mutationEpoch;sendingTargets.insert(target);issue=nil
    defer{sendingTargets.remove(target)}
    let pending:NativePendingPrompt
    do{pending=try await journal.prepare(target:target,files:files,skills:skills)}catch{if current==generation{issue = .storage};return}
    guard epoch==mutationEpoch,!Task.isCancelled else{
      // Durable intent exists, but no request was dispatched. Keep its draft editable.
      try? await journal.reject(pending);return
    }
    do{
      let result=try await service.send(target:target,input:pending.prompt)
      guard epoch==mutationEpoch else{try? await journal.mark(pending,state:.unknown);return}
      guard result.matches(pending.prompt,sessionID:target.sessionID) else{throw RemoteError.conflict}
      try await journal.confirm(pending)
    }catch{
      guard epoch==mutationEpoch else{
        if error is OpenCodePromptNotSubmitted{try? await journal.reject(pending)}
        else{try? await journal.mark(pending,state:.unknown)}
        return
      }
      if journal.storageIssue{if current==generation{issue = .storage};return}
      let resultIssue:NativeConversationIssue
      do{
        if let notSubmitted=error as? OpenCodePromptNotSubmitted{
          try await journal.reject(pending)
          resultIssue=switch notSubmitted.reason{
          case .unauthorized:.authenticationRequired
          case .conflict:.locationChanged
          case .incompatible:.incompatible
          default:.sendRejected
          }
        }else{
          switch error as? RemoteError{
          case .unauthorized,.forbidden,.invalidResponse,.notFound,.incompatible,.oversized:
            try await journal.reject(pending);resultIssue = .sendRejected
          default:
            let conflict=error as? RemoteError == .conflict
            try await journal.mark(pending,state:conflict ? .conflicting : .unknown)
            resultIssue=conflict ? .conflictingSend : .unknownSend
          }
        }
      }catch{if current==generation{issue = .storage};return}
      if current==generation{issue=resultIssue}
    }
    guard current==generation,epoch==mutationEpoch else{return}
    guard ![.authenticationRequired,.locationChanged,.incompatible].contains(issue) else{return}
    await refresh()
  }
  func interrupt() async {
    guard !stopping,let target,let service else{return}
    let current=generation;stopping=true
    defer{if current==generation{stopping=false}}
    do{
      _ = try await service.interrupt(target:target)
      guard current==generation else{return}
      // interrupted=false is an idle no-op; only readback controls the running indicator.
      await refresh()
    }catch{if current==generation{issue = .stopOutcomeUnknown}}
  }
  private func reconcile(target:OpenCodeTarget,page:OpenCodeMessagePage,inbox:[OpenCodeInboxItem],
                         service:any OpenCodeConversationServing,current:UUID) async throws {
    guard let pending=journal.pending(for:target) else{return}
    guard pending.target==target else{issue = .locationChanged;return}
    var matches:Bool?
    if let item=inbox.first(where:{$0.id==pending.prompt.id}) {
      matches=item.user?.matches(pending.prompt,sessionID:target.sessionID) ?? false
    }else{
      var read=page,cursors=Set<String>()
      for _ in 0..<20 {
        if let item=read.data.first(where:{$0.id==pending.prompt.id}) {
          matches=item.matches(pending.prompt);break
        }
        guard let cursor=read.cursor.next,cursors.insert(cursor).inserted else{break}
        read=try await service.messages(sessionID:target.sessionID,cursor:cursor)
        guard current==generation,!Task.isCancelled else{return}
      }
    }
    if matches == true {
      try await journal.confirm(pending)
      if current==generation,[.unknownSend,.conflictingSend].contains(issue){issue=nil}
    }else if matches == false {
      try await journal.mark(pending,state:.conflicting)
      if current==generation{issue = .conflictingSend}
    }else if current==generation {
      // Absence from a bounded read is not proof of rejection. No automatic resend.
      issue = .unknownSend
    }
  }
  private func subscribe(current:UUID,attempt:Int) async {
    guard current==generation,let service else{return}
    streamState = .connecting
    do{
      let source=try await service.events()
      guard current==generation,!Task.isCancelled else{return}
      streamState = .live;resyncSink?()
      consumer=Task{[weak self] in
        do{
          for try await event in source {
            guard let self,self.generation==current,!Task.isCancelled else{return}
            self.receive(event)
          }
          guard let self,self.generation==current,!Task.isCancelled else{return}
          self.recoverStream(current:current,attempt:attempt+1,overflow:false)
        }catch{
          guard let self,self.generation==current,!Task.isCancelled else{return}
          if error as? RemoteError == .unauthorized{self.issue = .authenticationRequired;self.streamState = .stopped;return}
          self.recoverStream(current:current,attempt:attempt+1,overflow:error as? RemoteError == .oversized)
        }
      }
    }catch{
      guard current==generation,!Task.isCancelled else{return}
      if error as? RemoteError == .unauthorized{issue = .authenticationRequired;streamState = .stopped;return}
      recoverStream(current:current,attempt:attempt+1,overflow:error as? RemoteError == .oversized)
    }
  }
  private func recoverStream(current:UUID,attempt:Int,overflow:Bool) {
    recovery?.cancel();streamState = .polling;liveText.reset()
    recovery=Task{[weak self] in
      guard let self else{return}
      self.resyncSink?();await self.refresh()
      if !overflow,attempt<3 {
        do{try await Task.sleep(for:.seconds(1<<attempt))}catch{return}
        await self.subscribe(current:current,attempt:attempt)
        if current==self.generation{await self.refresh()}
      }else{
        // A repeat oversized event must not cause an endless reconnect loop.
        while current==self.generation,!Task.isCancelled,self.issue != .authenticationRequired {
          do{try await Task.sleep(for:.seconds(5))}catch{return}
          self.resyncSink?();await self.refresh()
        }
      }
    }
  }
  func receive(_ event:OpenCodeEvent) {
    guard !seenEvents.contains(event.id) else{return}
    seenEvents.append(event.id);if seenEvents.count>512{seenEvents.removeFirst(seenEvents.count-512)}
    eventSink?(event)
    guard let target,event.affects(target) else{return}
    if let directory=event.location?.directory,event.data.sessionID==target.sessionID,!OpenCodeIdentity.matches(directory,target.directory){requestRefresh();return}
    let textUpdate=liveText.receive(event)
    if event.type=="session.text.delta",textUpdate == .updated{return}
    if ["session.reasoning.delta","session.tool.input.delta","session.compaction.delta"].contains(event.type){return}
    requestRefresh()
  }
  private func requestRefresh() {
    dirty=true;guard refreshTask==nil else{return}
    let current=generation
    refreshTask=Task{[weak self] in
      guard let self else{return}
      defer{if self.generation==current{self.refreshTask=nil}}
      do{try await Task.sleep(for:.milliseconds(200))}catch{return}
      while self.dirty,current==self.generation,!Task.isCancelled {
        self.dirty=false;await self.refresh()
        if self.dirty{do{try await Task.sleep(for:.milliseconds(200))}catch{return}}
      }
    }
  }
}
