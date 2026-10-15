import Foundation
import Observation
import OpenWorkRemoteCore

/// Composition for the existing app shell. Wire DTOs and credentials stay in
/// native services; the shell consumes the same pure conversation presentation.
@MainActor @Observable final class NativeAppCoordinator {
  let connection:ConnectionCoordinator
  let navigation=OpenCodeNavigationStore()
  let journal:NativeConversationJournal
  let conversation:ConversationCoordinator
  let controls=NativeControlStore()
  let approvals=NativeApprovalStore()
  let forms:NativeFormStore
  let visibility:NativeProjectVisibilityStore
  private(set) var ready=false
  var notice:String?
  private(set) var preservingEarlierHistory=false
  @ObservationIgnored private var activeClient:OpenCodeClient?
  @ObservationIgnored private var selection=UUID()
  @ObservationIgnored private var approvalTask:Task<Void,Never>?
  @ObservationIgnored private var formTask:Task<Void,Never>?
  @ObservationIgnored private var approvalsDirty=false
  @ObservationIgnored private var formsDirty=false
  init(directory:URL,connectionPersistence:OpenCodePersistence = .keychain,
       transport:any HTTPTransport=SessionTransport(profile:.openCode))throws {
    let root=try DraftStore(directory:directory).directory
    connection=ConnectionCoordinator(persistence:connectionPersistence,transport:transport)
    journal=NativeConversationJournal(persistence:try NativeConversationFile(directory:root))
    conversation=ConversationCoordinator(journal:journal)
    forms=NativeFormStore(persistence:try NativeFormFile(directory:root))
    visibility=NativeProjectVisibilityStore(persistence:try NativeVisibilityFile(directory:root))
    conversation.observe(snapshot:{[weak self] target,session,page in
      guard let self else{return}
      self.navigation.acceptNativeSnapshot(target:target,session:session,page:page,preserveWindow:self.preservingEarlierHistory)
    },event:{[weak self] event in self?.receive(event)},resync:{[weak self] in self?.refreshInputs()})
  }
  func start() async throws {
    try await journal.restore();try await forms.restore();try await visibility.restore();ready=true
    await connection.start();await connectionChanged()
  }
  func connectionChanged() async {
    guard connection.state == .ready,let client=connection.client,let saved=connection.connection else{return}
    guard activeClient !== client else{return}
    deactivate();activeClient=client;visibility.activate(saved.id);navigation.activate(saved,reader:client)
    await navigation.refreshProjects()
    do{try await visibility.observe(Set(navigation.projects.map(\.id)))}catch{notice="Project display preferences could not be saved."}
  }
  func open(_ session:OpenCodeSession) async {
    guard connection.state == .ready,let client=activeClient else{return}
    let current=UUID();selection=current;cancelInputs();preservingEarlierHistory=false
    guard let target=navigation.selectProvisional(session) else{return}
    controls.activate(target:target,client:client)
    approvals.activate(target:target,client:client);forms.activate(target:target,client:client)
    await conversation.activate(target:target,service:client)
    guard current==selection else{return}
    navigation.finishNativeRead(target:target,failed:conversation.currentSession==nil)
    if conversation.issue == .locationChanged{notice="This chat moved. Reopen it from Your Chats."}
    else if conversation.currentSession==nil{notice="This chat could not be loaded. Reconnect or try opening it again."}
  }
  func deactivate(){
    selection=UUID();cancelInputs()
    conversation.deactivate();controls.deactivate();approvals.deactivate();forms.deactivate();activeClient=nil
  }
  private func cancelInputs(){
    approvalTask?.cancel();formTask?.cancel();approvalTask=nil;formTask=nil;approvalsDirty=false;formsDirty=false
  }
  private func refreshInputs(){
    let current=selection
    if let context=approvals.context{
      approvalsDirty=true
      if approvalTask==nil{approvalTask=Task{[weak self] in
        guard let self else{return};defer{if self.selection==current{self.approvalTask=nil}}
        while self.selection==current,self.approvalsDirty,!Task.isCancelled{
          self.approvalsDirty=false;await self.approvals.refresh(context)
        }
      }}
    }
    if let context=forms.context{
      formsDirty=true
      if formTask==nil{formTask=Task{[weak self] in
        guard let self else{return};defer{if self.selection==current{self.formTask=nil}}
        while self.selection==current,self.formsDirty,!Task.isCancelled{
          self.formsDirty=false;await self.forms.refresh(context)
        }
      }}
    }
  }
  private func receive(_ event:OpenCodeEvent){
    guard let target=navigation.target,event.affects(target) else{return}
    if event.type.hasPrefix("form.") || event.type.hasPrefix("permission.") || event.type.hasPrefix("session.permission."){
      refreshInputs()
    }
  }
  var messages:[ChatMessage]{
    guard let target=navigation.target else{return []}
    return navigation.messages.compactMap{message in
      message.presentation(sessionID:target.sessionID,active:conversation.isActive){ordinal in
        conversation.liveText.text(messageID:message.id,ordinal:ordinal)
      }
    }
  }
  func olderMessages() async {preservingEarlierHistory=true;await navigation.loadOlder()}
}
