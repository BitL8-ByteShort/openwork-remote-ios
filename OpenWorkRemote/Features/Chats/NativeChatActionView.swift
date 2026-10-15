import OpenWorkRemoteCore
import SwiftUI

struct NativeChatActionView:View {
  @Bindable var native:NativeAppCoordinator
  let request:NativeChatActionRequest
  var onOpen:(()->Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var localError:String?
  @State private var performing=false
  @State private var visible=true
  private var store:NativeChatActionStore{native.chatActions}
  private var matching:Bool{native.connection.state == .ready && native.connection.connection?.id==request.target.connectionID && native.navigation.selectedProjectID==request.target.projectID && store.target==request.target}
  var body:some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:22){
          Text(request.deleting ? "Delete “\(request.session.title)” and its branches?":(request.beforeMessageID==nil ? "Continue in a new chat":"Fork before this message")).font(.title2.weight(.semibold))
          if request.deleting{
            Text("OpenCode permanently removes this chat, its history and every child branch. Files on the computer remain. This cannot be undone here.")
            Text("Branches created while deletion is happening may also be removed. Keep this tree idle on your computer until it finishes.").font(.callout).foregroundStyle(Theme.muted)
            if store.loading{ProgressView("Checking every branch…")}
            if let tree=store.tree{
              Text("\(tree.sessions.count) chat\(tree.sessions.count==1 ? "":"s") in this tree").font(.headline)
              ForEach(tree.sessions){row in Text(row.title ?? "Untitled chat").font(.callout).frame(maxWidth:.infinity,alignment:.leading)}
            }
          }else{
            Text(request.beforeMessageID==nil ? "Copy the settled conversation into a new chat with the current model and settings. The original chat stays intact.":"Copy only the messages before this one. This message and everything after it are excluded. The original chat stays intact.")
            Text("Keep the source chat idle while the copy is created.").font(.callout).foregroundStyle(Theme.muted)
          }
          if !matching{Text("The connection or project changed. Close this screen and open the action again.").foregroundStyle(Theme.muted)}
          if let notice=store.notice{Text(notice).foregroundStyle(Theme.muted).accessibilityIdentifier("native-action-notice")}
          if let localError{Text(localError).foregroundStyle(.red)}
          if store.pending != nil{
            Text("This saved action has not been confirmed. It will not be repeated automatically.").font(.callout)
            if case .delete=store.pending?.action{
              Button("Check deletion status"){Task{
                let ids:[String]=store.pending.flatMap{if case .delete(let tree)=$0.action{return tree.sessions.map(\.id)};return nil} ?? []
                if await store.checkDeletion(){await native.completeAction(.deleted,request:request.target,deletedIDs:ids);dismiss()}
              }}.disabled(store.busy || !matching)
            }
            Button("Review recent chats"){Task{await native.reviewActionChats(target:request.target)}}.disabled(store.busy || !matching)
            if store.reviewed{
              ForEach(store.reviewedChats.prefix(8)){chat in Text(chat.title ?? "Untitled chat").font(.callout)}
              Text("These titles do not confirm which action succeeded. Check the computer before clearing this saved uncertainty.").font(.caption).foregroundStyle(Theme.muted)
              Button("Keep current chats"){Task{do{try await store.keepCurrentChats();dismiss()}catch{localError="The saved action could not be cleared."}}}.disabled(store.busy || !matching)
            }
          }else{
            Button{Task{await confirm()}}label:{
              HStack{if store.busy || performing{ProgressView().tint(.white)};Text(request.deleting ? "Delete this chat and branches":"Create new chat")}.frame(maxWidth:.infinity)
            }.buttonStyle(PrimaryButtonStyle(fill:request.deleting ? .red:Theme.accent,ink:request.deleting ? .white:Theme.onAccent))
              .disabled(!matching || !store.ready || store.busy || performing || store.loading || store.storageIssue || (request.deleting && store.tree==nil)).accessibilityIdentifier("native-action-confirm")
            if request.deleting{Button("Refresh branch tree"){Task{await store.loadTree()}}.disabled(store.busy || store.loading || !matching)}
          }
          if store.busy{Text("Closing this screen does not undo a request already sent to OpenCode.").font(.caption).foregroundStyle(Theme.muted)}
        }.padding(24)
      }.background(Theme.background).navigationTitle(request.deleting ? "Delete chat":"Continue chat").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button(store.busy ? "Close":"Cancel"){dismiss()}}}
    }.onDisappear{visible=false}.task{
      guard let client=native.connection.client,native.connection.connection?.id==request.target.connectionID,native.navigation.selectedProjectID==request.target.projectID else{return}
      store.activate(target:request.target,client:client)
      if request.deleting,store.pending==nil{await store.loadTree()}
    }
  }
  private func confirm()async{
    guard matching,!performing else{return}
    performing=true;defer{performing=false}
    let action:NativeChatAction
    if request.deleting{guard let tree=store.tree else{return};action = .delete(tree)}else{action = .fork(beforeMessageID:request.beforeMessageID)}
    let ids=store.tree?.sessions.map(\.id) ?? [],generation=native.selectionGeneration
    if let result=await store.perform(action){
      if visible,native.selectionGeneration==generation{dismiss();if !request.deleting{onOpen?()}}
      await native.completeAction(result,request:request.target,deletedIDs:ids,generation:generation)
    }
  }
}
