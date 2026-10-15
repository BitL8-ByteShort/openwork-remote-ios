import Foundation
import Observation
import OpenWorkRemoteCore

enum NativeStartupState{case loading,ready,storageUnavailable}
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
  private(set) var results:NativeResultStore
  let visibility:NativeProjectVisibilityStore
  let creation:NativeCreateStore
  var newChatLocationRequest:NativeChatLocationRequest?
  let chatActions:NativeChatActionStore
  let groups:LocalChatGroupStore
  let search=NativeChatSearchStore()
  let workspace:NativeWorkspaceStore
  let defaults:LocalChatDefaultsStore
  let lastSelection:NativeSelectionStore
  let sharing:ProviderDisclosureStore
  private(set) var preparingSend=false
  @ObservationIgnored private var sendPreparation=UUID()
  private(set) var ready=false
  private(set) var startupState:NativeStartupState = .loading
  @ObservationIgnored private var starting=false
  @ObservationIgnored private var retired=false
  @ObservationIgnored private let storageDirectory:URL
  @ObservationIgnored private let savedConnectionPersistence:OpenCodePersistence
  @ObservationIgnored private let savedTransport:any HTTPTransport
  @ObservationIgnored private let localFiles:NativeLocalDataFiles
  var notice:String?
  private(set) var preservingEarlierHistory=false
  @ObservationIgnored private var activeClient:OpenCodeClient?
  @ObservationIgnored private var selection=UUID()
  var selectionGeneration:UUID{selection}
  @ObservationIgnored private var approvalTask:Task<Void,Never>?
  @ObservationIgnored private var formTask:Task<Void,Never>?
  @ObservationIgnored private var approvalsDirty=false
  @ObservationIgnored private var formsDirty=false
  @ObservationIgnored private var controlTask:Task<Void,Never>?
  @ObservationIgnored private var controlsDirty=false
  init(directory:URL,connectionPersistence:OpenCodePersistence = .keychain,
       transport:any HTTPTransport=SessionTransport(profile:.openCode))throws {
    let root=try DraftStore(directory:directory).directory
    storageDirectory=root;savedConnectionPersistence=connectionPersistence;savedTransport=transport
    let localFiles=try NativeLocalDataFiles(directory:root);self.localFiles=localFiles
    connection=ConnectionCoordinator(persistence:connectionPersistence,transport:transport)
    journal=NativeConversationJournal(persistence:localFiles.conversations)
    conversation=ConversationCoordinator(journal:journal)
    workspace=NativeWorkspaceStore(journal:journal)
    defaults=LocalChatDefaultsStore(persistence:localFiles.defaults)
    lastSelection=NativeSelectionStore(file:localFiles.selection)
    sharing=ProviderDisclosureStore(persistence:localFiles.sharing)
    attachments=NativeAttachmentStore(journal:journal,files:ProtectedAttachmentFiles(directory:root.appending(path:"NativeAttachmentBytes")))
    results=NativeResultStore(files:ProtectedArtifactFiles(directory:root.appending(path:"NativeDownloads")))
    forms=NativeFormStore(persistence:localFiles.forms)
    visibility=NativeProjectVisibilityStore(persistence:localFiles.visibility)
    creation=NativeCreateStore(persistence:localFiles.creation)
    chatActions=NativeChatActionStore(persistence:localFiles.actions)
    groups=LocalChatGroupStore(persistence:localFiles.groups)
    connection.observeChanges{[weak self] in
      guard let self else{return}
      // Stop child work immediately, independent of a SwiftUI observation turn.
      if self.connection.state != .ready || self.activeClient !== self.connection.client{self.deactivate()}
    }
    conversation.observe(snapshot:{[weak self] target,session,page in
      guard let self else{return}
      self.navigation.acceptNativeSnapshot(target:target,session:session,page:page,preserveWindow:self.preservingEarlierHistory)
      self.results.updateReferences(self.navigation.messages,target:target)
    },event:{[weak self] event in self?.receive(event)},resync:{[weak self] in self?.refreshInputs();self?.refreshControls()})
    controls.observeSession{[weak self] target,session in
      guard let self,self.navigation.target==target else{return}
      self.navigation.acceptChat(session)
    }
  }
  func start() async throws {
    guard !retired,!starting,!ready else{return};starting=true;startupState = .loading
    defer{starting=false}
    do{
      try await journal.restore();try await forms.restore();try await visibility.restore();try await creation.restore();try await chatActions.restore();try await groups.restore();try await defaults.restore();try await lastSelection.restore();try await sharing.restore()
    }catch{ready=false;startupState = .storageUnavailable;throw error}
    ready=true;startupState = .ready
    try? await results.files.cleanup()
    await connection.start();await connectionChanged()
  }
  func connectionChanged() async {
    guard ready,!retired,connection.state == .ready,let client=connection.client,let saved=connection.connection else{return}
    guard activeClient !== client else{return}
    deactivate();activeClient=client
    await client.observeSharingAuthorization{[weak self,weak client] target,classes,operation in
      guard let self,let client else{throw RemoteError.forbidden}
      try await self.requireSharing(target:target,client:client,classes:classes,operation:operation)
    }
    guard activeClient === client,connection.state == .ready else{return}
    visibility.activate(saved.id);navigation.activate(saved,reader:client)
    creation.activate(connectionID:saved.id,client:client)
    let picked=selection
    await navigation.refreshProjects()
    guard activeClient === client,connection.state == .ready else{return}
    activateProjectStores()
    do{try await visibility.observe(Set(navigation.projects.map(\.id)))}catch{notice="Project display preferences could not be saved."}
    guard selection==picked,activeClient === client,connection.state == .ready else{return}
    await restoreSelection(client:client,connection:saved,picked:picked)
  }
  func open(_ session:OpenCodeSession) async {
    guard connection.state == .ready,let client=activeClient else{return}
    let current=UUID();selection=current;cancelInputs();cancelSendPreparation();preservingEarlierHistory=false
    guard let target=navigation.selectProvisional(session) else{return}
    sharing.activate(target)
    attachments.activate(target:target,client:client);results.activate(target:target,client:client)
    workspace.activate(target:target,client:client)
    controls.activate(target:target,client:client)
    approvals.activate(target:target,client:client);forms.activate(target:target,client:client)
    await conversation.activate(target:target,service:client)
    guard current==selection else{return}
    navigation.finishNativeRead(target:target,failed:conversation.currentSession==nil)
    if conversation.issue == .locationChanged{notice="This chat moved. Reopen it from Your Chats."}
    else if conversation.currentSession==nil{notice="This chat could not be loaded. Reconnect or try opening it again."}
    else{await rememberSelection(chat:target)}
  }
  private func restoreSelection(client:OpenCodeClient,connection:OpenCodeConnection,picked:UUID)async{
    guard let saved=lastSelection.value(for:connection.id),
      navigation.projects.contains(where:{OpenCodeIdentity.matches($0.id,saved.projectID)}),visibility.policy.shows(saved.projectID) else{return}
    if !OpenCodeIdentity.matches(navigation.selectedProjectID ?? "",saved.projectID){await navigation.selectProject(saved.projectID)}
    guard selection==picked,activeClient === client,self.connection.state == .ready else{return}
    activateProjectStores()
    guard let target=saved.chat else{return}
    do{
      let actual=try await client.session(id:target.sessionID)
      guard selection==picked,activeClient === client,self.connection.state == .ready else{return}
      guard actual.time.archived==nil,OpenCodeIdentity.matches(actual.id,target.sessionID),
        OpenCodeIdentity.matches(actual.projectID,target.projectID),OpenCodeIdentity.matches(actual.location.directory,target.directory) else{
        notice="The previous chat moved or is no longer available. Open it from Your Chats; its earlier draft remains in local recovery."
        await rememberSelection(chat:nil);return
      }
      navigation.acceptChat(actual);await open(actual)
    }catch{
      guard selection==picked,activeClient === client else{return}
      notice="The previous chat could not be restored. Its saved draft is still on this device."
      if error as? RemoteError == .notFound{await rememberSelection(chat:nil)}
    }
  }
  func rememberSelection(chat:OpenCodeTarget?)async{
    guard let connection=connection.connection,let projectID=navigation.selectedProjectID else{return}
    do{try await lastSelection.remember(connection:connection.id,projectID:projectID,chat:chat)}
    catch{notice="The last-opened chat could not be saved. Your draft is stored separately."}
  }
  func deactivate(){
    selection=UUID();cancelInputs();cancelSendPreparation()
    sharing.activate(nil)
    workspace.deactivate();defaults.activate(nil)
    conversation.deactivate();attachments.deactivate();results.deactivate();controls.deactivate();approvals.deactivate();forms.deactivate();creation.deactivate();chatActions.deactivate();groups.activate(nil);search.activate(nil,reader:nil);newChatLocationRequest=nil;activeClient=nil
  }
  private func cancelInputs(){
    approvalTask?.cancel();formTask?.cancel();approvalTask=nil;formTask=nil;approvalsDirty=false;formsDirty=false
    controlTask?.cancel();controlTask=nil;controlsDirty=false
  }
  private func refreshControls(){
    // Closed settings need no catalog fetch: the conversation refresh updates
    // its header. Keep an already-open settings snapshot current as well.
    guard let context=controls.context,controls.snapshot != nil else{return}
    let current=selection;controlsDirty=true
    guard controlTask==nil else{return}
    controlTask=Task{[weak self] in
      guard let self else{return}
      defer{if self.selection==current{self.controlTask=nil}}
      while self.selection==current,self.controlsDirty,!Task.isCancelled{
        self.controlsDirty=false
        if self.controls.busy{
          // A mutation owns its readback; do not supersede it with a hint.
          do{try await Task.sleep(for:.milliseconds(100))}catch{return}
          self.controlsDirty=true
        }else{await self.controls.load(context)}
      }
    }
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
    if ["session.model.selected","session.agent.selected","server.connected"].contains(event.type){refreshControls()}
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
  var uncertain:Bool{
    guard let target=navigation.target,let pending=journal.pending(for:target) else{return false}
    return pending.state != .prepared || !conversation.sending
  }
  var canSend:Bool{
    connection.state == .ready && ready && journal.ready && !journal.storageIssue && !uncertain &&
      !(navigation.target.map{chatActions.blocks($0)} ?? true) &&
      conversation.currentSession != nil && conversation.target==navigation.target && !conversation.sending && !preparingSend && !conversation.isActive &&
      (!draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || attachments.canSend || !workspace.selectedSkills.isEmpty) &&
      (attachments.rows.isEmpty || attachments.canSend) && draft.utf8.count<=32_768
  }
  func setDraft(_ value:String){if let target=navigation.target{journal.setDraft(value,for:target)}}
  func select(_ presentation:ChatSession) async {
    guard let session=navigation.sessions.first(where:{OpenCodeIdentity.matches($0.id,presentation.id) && OpenCodeIdentity.matches($0.projectID,presentation.workspaceId)}) else{return}
    await open(session)
  }
  private func cancelSendPreparation(){sendPreparation=UUID();preparingSend=false}
  private func authorizeSharing(target:OpenCodeTarget,client:OpenCodeClient,classes:Set<OpenCodeSharedData>,operation:OpenCodeSharingOperation)async->Bool{
    guard activeClient === client,connection.state == .ready,navigation.target==target else{return false}
    return await sharing.authorize(target:target,reader:client,classes:classes,operation:operation)
  }
  private func requireSharing(target:OpenCodeTarget,client:OpenCodeClient,classes:Set<OpenCodeSharedData>,operation:OpenCodeSharingOperation)async throws{
    guard activeClient === client,connection.state == .ready,navigation.target==target else{throw RemoteError.forbidden}
    try await sharing.requireAuthorization(target:target,reader:client,classes:classes,operation:operation)
  }
  func send() async {
    guard canSend,let context=workspace.context,context.target==navigation.target else{return}
    let id=UUID();sendPreparation=id;preparingSend=true
    defer{if sendPreparation==id{preparingSend=false}}
    let text=draft,selected=attachments.rows,chosen=workspace.selectedSkills
    guard let client=activeClient else{return}
    var classes=OpenCodeSharedData.conversationContext
    for row in selected{classes.insert(row.file.mime=="image/png" ? .photos:.documents)}
    if !chosen.isEmpty{classes.insert(.skillInstructions)}
    guard await authorizeSharing(target:context.target,client:client,classes:classes,operation:.message) else{
      if sendPreparation==id{notice=sharing.notice};return
    }
    guard sendPreparation==id,navigation.target==context.target,activeClient === client else{return}
    notice=nil
    guard let skills=await workspace.validatedSkills(context) else{
      if sendPreparation==id{notice=workspace.skillsNotice ?? "The selected skills could not be checked. Review them before sending."};return
    }
    do{
      let files:[OpenCodePromptFile]
      if selected.isEmpty{files=[]}
      else{
        guard let fileContext=attachments.context,fileContext.target==context.target else{return}
        files=try await attachments.promptFiles(context:fileContext)
      }
      guard sendPreparation==id,navigation.target==context.target,conversation.target==context.target else{return}
      guard OpenCodeIdentity.matches(text,draft),chosen==workspace.selectedSkills,
        selected.map(\.id)==attachments.rows.map(\.id),selected.map(\.prepared)==attachments.rows.map(\.prepared) else{
        notice="Your draft or selected items changed during the check. Review them and tap Send again.";return
      }
      await conversation.send(files:files,skills:skills)
      if !journal.storageIssue,journal.pending(for:context.target)==nil{
        let retained=Set(journal.attachments(for:context.target).map(\.id))
        for row in selected where !retained.contains(row.id){try? await attachments.files.remove(row.file)}
      }
    }catch{if sendPreparation==id{notice="The selected files could not be read safely. Unlock this device or remove and choose them again."}}
  }
  func stop() async {await conversation.interrupt()}
  func checkConversation() async {await conversation.refresh()}
  func changeWorkspace(_ workspace:Workspace) async {
    guard connection.state == .ready else{return}
    let picked=UUID();selection=picked;cancelInputs();cancelSendPreparation();self.workspace.deactivate();conversation.clearSelection();attachments.clearSelection();results.deactivate();controls.deactivate();approvals.deactivate();forms.clearSelection()
    newChatLocationRequest=nil;groups.activate(nil);search.activate(nil,reader:nil);sharing.activate(nil)
    await navigation.selectProject(workspace.id)
    guard selection==picked,connection.state == .ready else{return}
    activateProjectStores();await rememberSelection(chat:nil)
  }
  func sceneActive(_ active:Bool)async{
    if !active{deactivate();await connection.sceneActive(false);return}
    guard ready,!Task.isCancelled else{return}
    await connection.sceneActive(true)
    guard !Task.isCancelled else{return}
    await connectionChanged()
  }
  func reconnect() async {
    guard ready,!retired else{return}
    if connection.state == .authenticationRejected{connection.pairAgain();return}
    await connection.reconnect();await connectionChanged()
  }
  func jumpToLatest(){preservingEarlierHistory=false;navigation.showLatestSnapshot();if let target=navigation.target{results.updateReferences(navigation.messages,target:target)}}
  func followLatest(_ following:Bool){
    if following{if preservingEarlierHistory{jumpToLatest()}}
    else{preservingEarlierHistory=true}
  }
  func forget(){
    deactivate();connection.forgetLocalConnection()
    if connection.state == .unpaired{navigation.deactivate()}
    else{notice="The saved connection could not be removed. Unlock this device and try again."}
  }
  func stopLocalWork(){deactivate();connection.retireRequests()}
  func resetLocalFiles()async->[String]{
    retired=true;ready=false;stopLocalWork();journal.retire();forms.retire()
    // All snapshot writers and both byte stores retire before the first removal.
    await localFiles.retireWriters();await attachments.files.retire();await results.files.retire()
    var failures=await localFiles.removeAll()
    do{try await attachments.files.invalidateAndRemove()}catch{failures.append("OpenCode selected attachment copies")}
    do{try await results.files.invalidateAndRemove()}catch{failures.append("OpenCode downloaded and preview copies")}
    navigation.deactivate();return failures
  }
  func clearDownloadedCopies()async throws{
    guard !retired else{throw RemoteError.cancelled}
    let old=results;old.deactivate()
    do{try await old.files.invalidateAndRemove()}
    catch{
      results=NativeResultStore(files:ProtectedArtifactFiles(directory:storageDirectory.appending(path:"NativeDownloads")))
      restoreResultContext();throw error
    }
    results=NativeResultStore(files:ProtectedArtifactFiles(directory:storageDirectory.appending(path:"NativeDownloads")))
    restoreResultContext()
  }
  private func restoreResultContext(){
    if let target=navigation.target,let client=activeClient,connection.state == .ready{
      results.activate(target:target,client:client);results.updateReferences(navigation.messages,target:target)
    }
  }
  func freshAfterReset()throws->NativeAppCoordinator{
    guard retired else{throw RemoteError.invalidResponse}
    return try NativeAppCoordinator(directory:storageDirectory,connectionPersistence:savedConnectionPersistence,transport:savedTransport)
  }
  func olderMessages() async {preservingEarlierHistory=true;await navigation.loadOlder();if let target=navigation.target{results.updateReferences(navigation.messages,target:target)}}
}
