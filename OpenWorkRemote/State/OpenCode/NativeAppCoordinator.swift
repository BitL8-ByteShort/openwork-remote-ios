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
  let attachments:NativeAttachmentStore
  let results:NativeResultStore
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
    attachments=NativeAttachmentStore(journal:journal,files:ProtectedAttachmentFiles(directory:root.appending(path:"NativeAttachmentBytes")))
    results=NativeResultStore(files:ProtectedArtifactFiles(directory:root.appending(path:"NativeDownloads")))
    forms=NativeFormStore(persistence:try NativeFormFile(directory:root))
    visibility=NativeProjectVisibilityStore(persistence:try NativeVisibilityFile(directory:root))
    conversation.observe(snapshot:{[weak self] target,session,page in
      guard let self else{return}
      self.navigation.acceptNativeSnapshot(target:target,session:session,page:page,preserveWindow:self.preservingEarlierHistory)
      self.results.updateReferences(self.navigation.messages,target:target)
    },event:{[weak self] event in self?.receive(event)},resync:{[weak self] in self?.refreshInputs()})
  }
  func start() async throws {
    try await journal.restore();try await forms.restore();try await visibility.restore();ready=true
    try? await results.files.cleanup()
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
    attachments.activate(target:target,client:client);results.activate(target:target,client:client)
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
    conversation.deactivate();attachments.deactivate();results.deactivate();controls.deactivate();approvals.deactivate();forms.deactivate();activeClient=nil
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
  var connectionState:ConnectionState{
    switch connection.state{
    case .unpaired:return .unpaired
    case .pairing:return .pairing
    case .connecting:return .connecting
    case .ready:return .ready
    case .offline,.storageUnavailable:return .offline
    case .authenticationRejected:return .revoked
    case .incompatible:return .incompatible
    }
  }
  var workspaces:[Workspace]{navigation.projects.filter{visibility.policy.shows($0.id)}.map(\.presentation)}
  var sessions:[ChatSession]{navigation.sessions.map{sessionPresentation($0)}}
  var selectedSession:ChatSession?{navigation.selectedSession.map{sessionPresentation($0)}}
  private func sessionPresentation(_ session:OpenCodeSession)->ChatSession{
    session.presentation(active:conversation.isActive && session.id==navigation.target?.sessionID,modelLabel:session.model?.id)
  }
  var draft:String{navigation.target.map{journal.draft(for:$0)} ?? ""}
  var uncertain:Bool{navigation.target.map{journal.pending(for:$0) != nil} ?? false}
  var canSend:Bool{
    connection.state == .ready && ready && journal.ready && !journal.storageIssue && !uncertain &&
      conversation.currentSession != nil && conversation.target==navigation.target && !conversation.sending && !conversation.isActive &&
      (!draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || attachments.canSend) &&
      (attachments.rows.isEmpty || attachments.canSend) && draft.utf8.count<=32_768
  }
  func setDraft(_ value:String){if let target=navigation.target{journal.setDraft(value,for:target)}}
  func select(_ presentation:ChatSession) async {
    guard let session=navigation.sessions.first(where:{OpenCodeIdentity.matches($0.id,presentation.id) && OpenCodeIdentity.matches($0.projectID,presentation.workspaceId)}) else{return}
    await open(session)
  }
  func send() async {
    guard canSend else{return}
    if attachments.rows.isEmpty{await conversation.send();return}
    guard let context=attachments.context else{return}
    let selected=attachments.rows
    do{
      let files=try await attachments.promptFiles(context:context)
      guard navigation.target==context.target,conversation.target==context.target else{
        notice="The chat changed before the files were sent. Your selected files stay with the original chat.";return
      }
      await conversation.send(files:files)
      if !journal.storageIssue,journal.pending(for:context.target)==nil{
        let retained=Set(journal.attachments(for:context.target).map(\.id))
        for row in selected where !retained.contains(row.id){try? await attachments.files.remove(row.file)}
      }
    }catch{notice="The selected files could not be read safely. Unlock this device or remove and choose them again."}
  }
  func stop() async {await conversation.interrupt()}
  func checkConversation() async {await conversation.refresh()}
  func changeWorkspace(_ workspace:Workspace) async {
    guard connection.state == .ready else{return}
    selection=UUID();cancelInputs();conversation.clearSelection();attachments.clearSelection();results.deactivate();controls.deactivate();approvals.deactivate();forms.clearSelection()
    await navigation.selectProject(workspace.id)
  }
  func reconnect() async {
    if connection.state == .authenticationRejected{connection.pairAgain();return}
    await connection.reconnect();await connectionChanged()
  }
  func jumpToLatest(){preservingEarlierHistory=false;navigation.showLatestSnapshot();if let target=navigation.target{results.updateReferences(navigation.messages,target:target)}}
  func followLatest(_ following:Bool){if !following{preservingEarlierHistory=true}}
  func forget(){
    deactivate();connection.forgetLocalConnection()
    if connection.state == .unpaired{navigation.deactivate()}
    else{notice="The saved connection could not be removed. Unlock this device and try again."}
  }
  func olderMessages() async {preservingEarlierHistory=true;await navigation.loadOlder();if let target=navigation.target{results.updateReferences(navigation.messages,target:target)}}
}
