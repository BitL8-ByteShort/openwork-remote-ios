import Foundation
import OpenWorkRemoteCore

struct NativeChatLocationRequest:Identifiable {
  let id=UUID()
  let scope:NativeProjectKey
  let directories:[String]
}
struct NativeRenameReview:Sendable {
  let target:OpenCodeTarget
  let expectedTitle:String?
}
extension NativeAppCoordinator {
  var projectKey:NativeProjectKey?{
    guard let connection=connection.connection,let projectID=navigation.selectedProjectID else{return nil}
    return NativeProjectKey(connectionID:connection.id,projectID:projectID)
  }
  func activateProjectStores(){
    groups.activate(projectKey);defaults.activate(projectKey);search.activate(projectKey,reader:connection.client)
  }
  var newChatLocations:[String]{
    guard let projectID=navigation.selectedProjectID else{return []}
    if let target=navigation.target,target.projectID==projectID,target.directory != "/"{return [target.directory]}
    if let project=navigation.projects.first(where:{$0.id==projectID}),project.canonical != "/"{return [project.canonical]}
    return navigation.sessions.filter{$0.projectID==projectID && $0.time.archived==nil && $0.location.directory != "/"}
      .map(\.location.directory).reduce(into:[String]()){list,path in
        if !list.contains(where:{OpenCodeIdentity.matches($0,path)}){list.append(path)}
      }.sorted()
  }
  var canCreateChat:Bool{connection.state == .ready && defaults.ready && !defaults.busy && defaults.scope==projectKey && !navigation.loadingMessages && creation.canCreate && !newChatLocations.isEmpty}
  @discardableResult func createChat(directory:String?=nil,onCreated:(()->Void)?=nil)async->Bool{
    guard canCreateChat,let projectID=navigation.selectedProjectID,let scope=projectKey else{
      notice="Open an existing project location on your computer before creating a chat.";return false
    }
    let locations=newChatLocations
    let selected:String
    if let directory{
      guard locations.contains(where:{OpenCodeIdentity.matches($0,directory)}) else{return false};selected=directory
    }else{
      guard locations.count==1 else{newChatLocationRequest=NativeChatLocationRequest(scope:scope,directories:locations);return false};selected=locations[0]
    }
    newChatLocationRequest=nil
    let epoch=connection.client,picked=selectionGeneration
    let preferences=defaults.value
    let session=await creation.create(projectID:projectID,directory:selected,model:preferences.model,agent:preferences.agent)
    guard let session,connection.client === epoch,connection.state == .ready,navigation.selectedProjectID==projectID else{
      notice=creation.notice;return false
    }
    navigation.acceptChat(session)
    guard selectionGeneration==picked else{notice="New chat created. Open it from Your Chats.";return false}
    onCreated?();await open(session);return true
  }
  func checkCreatedChat()async{
    let epoch=connection.client,projectID=navigation.selectedProjectID,picked=selectionGeneration
    if let session=await creation.check(),connection.client === epoch,session.projectID==projectID{
      navigation.acceptChat(session)
      if selectionGeneration==picked{await open(session)}else{notice="The new chat was found. Open it from Your Chats."}
    }else{notice=creation.notice}
  }
  func renameReview(_ session:ChatSession)->NativeRenameReview?{
    guard connection.state == .ready,let connection=connection.connection,
      let actual=navigation.sessions.first(where:{$0.id==session.id && $0.projectID==session.workspaceId}),
      actual.time.archived==nil else{return nil}
    return NativeRenameReview(target:OpenCodeTarget(connectionID:connection.id,projectID:actual.projectID,
      sessionID:actual.id,directory:actual.location.directory),expectedTitle:actual.title)
  }
  func rename(_ review:NativeRenameReview,title:String)async throws{
    guard connection.state == .ready,let client=connection.client,connection.connection?.id==review.target.connectionID else{throw RemoteError.unavailable}
    let session:OpenCodeSession
    do{session=try await client.rename(target:review.target,title:title,expectedTitle:review.expectedTitle)}
    catch let rejected as OpenCodeChatNotSubmitted{throw rejected.reason}
    guard connection.client === client else{throw RemoteError.cancelled}
    navigation.acceptChat(session)
    if navigation.target==review.target{await conversation.refresh()}
  }
}

extension NativeAppCoordinator {
  func actionTarget(_ session:ChatSession)->OpenCodeTarget?{renameReview(session)?.target}
  func completeAction(_ result:NativeActionResult,request:OpenCodeTarget,deletedIDs:[String],generation:UUID?=nil)async{
    guard connection.state == .ready,connection.connection?.id==request.connectionID,navigation.selectedProjectID==request.projectID else{return}
    switch result{
    case .fork(let session):
      navigation.acceptChat(session)
      guard generation==selectionGeneration else{notice="The copied chat is ready in Your Chats.";return}
      await open(session)
    case .deleted:
      if let selected=navigation.target,deletedIDs.contains(selected.sessionID){
        workspace.deactivate();conversation.clearSelection();attachments.clearSelection();results.deactivate();controls.deactivate();approvals.deactivate();forms.clearSelection()
      }
      navigation.removeChats(Set(deletedIDs))
    }
  }
  func reviewActionChats(target:OpenCodeTarget)async{
    guard connection.state == .ready,let client=connection.client,connection.connection?.id==target.connectionID,navigation.selectedProjectID==target.projectID else{return}
    do{
      let page=try await client.sessions(projectID:target.projectID,cursor:nil,search:nil)
      guard connection.client === client,navigation.selectedProjectID==target.projectID,chatActions.target==target else{return}
      for row in page.data.reversed(){navigation.acceptChat(row)}
      chatActions.markReviewed(page.data)
    }catch{notice="Recent chats could not be refreshed. Keep the saved uncertainty and reconnect."}
  }
}
