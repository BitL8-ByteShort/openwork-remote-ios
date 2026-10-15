import OpenWorkRemoteCore
import SwiftUI

struct NativeRenameRequest:Identifiable {
  let id=UUID()
  let session:ChatSession
  let review:NativeRenameReview
}
struct NativeChatActionRequest:Identifiable {
  let id=UUID()
  let session:ChatSession
  let target:OpenCodeTarget
  let deleting:Bool
  var beforeMessageID:String?=nil
}
struct NativeChatListView:View {
  @Bindable var native:NativeAppCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var query=""
  @State private var settings=false
  @State private var renaming:NativeRenameRequest?
  @State private var action:NativeChatActionRequest?
  @State private var managing=false
  @State private var moving:ChatSession?
  @State private var filter:UUID?
  @State private var onlyUngrouped=false
  var body:some View{
    NavigationStack{
      List{
        Section("Projects"){
          ForEach(native.workspaces){project in
            Button{Task{await native.changeWorkspace(project)}}label:{
              HStack{Image(systemName:"folder");Text(project.name);Spacer();if project.id==native.navigation.selectedProjectID{Image(systemName:"checkmark").foregroundStyle(Theme.accent)}}
                .foregroundStyle(Theme.ink)
            }
          }
        }
        Section{
          Button{managing=true}label:{Label("Manage groups",systemImage:"folder.badge.gearshape")}.accessibilityIdentifier("groups-manage")
          if !native.groups.snapshot.groups.isEmpty{
            ScrollView(.horizontal){HStack{
              filterButton("All chats",id:nil)
              ForEach(native.groups.snapshot.groups){group in filterButton(group.label,id:group.id)}
              Button("No group"){filter=nil;onlyUngrouped=true}.frame(minHeight:44)
            }}
          }
          Text(NativeGroupEditor.localLabel+". Groups do not sync to OpenCode.").font(.caption).foregroundStyle(Theme.muted)
        }header:{Text("Groups")}
        if native.creation.pending != nil{
          Section{
            Text("New chat creation has not been confirmed.")
            Button("Check creation status"){Task{await native.checkCreatedChat()}}.disabled(native.creation.busy)
            if native.creation.reviewed{
              Text("It may still appear later. Review chats on the computer before continuing.").font(.caption)
              Button("Keep current chats"){Task{do{try await native.creation.acknowledgeUncertainty()}catch{native.notice="The saved creation could not be cleared."}}}
            }
            if let notice=native.creation.notice{Text(notice).font(.caption)}
          }
        }
        Section{
          NavigationLink{NativeChatSearchView(native:native,onOpen:{dismiss()})}label:{Label("Search older chat titles",systemImage:"magnifyingglass")}
            .accessibilityIdentifier("older-search-open")
        }
        Section{
          if results.isEmpty{Text(query.isEmpty ? "No chats in this view.":"No matches in loaded titles.").foregroundStyle(Theme.muted)}
          ForEach(results){session in row(session)}
        }header:{Text(filter.flatMap{id in native.groups.snapshot.groups.first{$0.id==id}?.label} ?? (onlyUngrouped ? "No group":"Recent chats"))}
        if native.navigation.sessionCursor != nil{
          Button("Load older chats"){Task{await native.navigation.loadMoreSessions()}}.disabled(native.navigation.loadingSessions)
        }
        if native.navigation.loadingSessions{ProgressView("Loading chats…")}
        if let notice=native.notice{Section{Text(notice).font(.callout).foregroundStyle(Theme.muted)}}
      }.scrollContentBackground(.hidden).background(Theme.background)
        .searchable(text:$query,prompt:"Search loaded titles").navigationTitle("Your chats")
        .toolbar{
          ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}.accessibilityIdentifier("native-chatlist-done")}
          ToolbarItem(placement:.primaryAction){Button{Task{await native.createChat(onCreated:{dismiss()})}}label:{Image(systemName:"square.and.pencil")}.disabled(!native.canCreateChat).accessibilityLabel("New chat").accessibilityIdentifier("native-list-new-chat")}
          ToolbarItem(placement:.bottomBar){Button{managing=true}label:{Label("New group",systemImage:"folder.badge.plus")}.accessibilityIdentifier("groups-new")}
          ToolbarItem(placement:.bottomBar){Button{settings=true}label:{Label("Settings",systemImage:"gearshape")}}
        }
        .sheet(isPresented:$settings){ConnectionView()}
        .sheet(item:$renaming){RenameChatView(session:$0.session,nativeReview:$0.review)}
        .sheet(item:$action){NativeChatActionView(native:native,request:$0,onOpen:{dismiss()})}
        .sheet(isPresented:$managing){NativeGroupEditor(native:native)}
        .sheet(item:$moving){NativeMoveChatView(native:native,session:$0)}
        .sheet(item:$native.newChatLocationRequest){NativeChatLocationView(native:native,request:$0,onOpen:{dismiss()})}
        .onChange(of:native.projectKey){_,_ in filter=nil;onlyUngrouped=false}
    }
  }
  private var results:[ChatSession]{
    native.sessions.filter{session in
      (query.isEmpty || session.title.localizedCaseInsensitiveContains(query)) &&
      (filter.map{native.groups.snapshot.assignments[session.id]==$0} ?? (!onlyUngrouped || native.groups.snapshot.assignments[session.id]==nil))
    }
  }
  private func filterButton(_ title:String,id:UUID?)->some View{
    Button(title){filter=id;onlyUngrouped=false}.padding(.horizontal,12).frame(minHeight:44)
      .background(filter==id && !onlyUngrouped ? Theme.surface:Theme.background,in:Capsule())
      .accessibilityAddTraits(filter==id && !onlyUngrouped ? .isSelected:[])
  }
  private func row(_ session:ChatSession)->some View{
    HStack(spacing:8){
      Button{dismiss();Task{await native.select(session)}}label:{
        VStack(alignment:.leading,spacing:6){Text(session.title).foregroundStyle(Theme.ink).lineLimit(2);if let label=session.modelLabel{Text(label).font(.caption).foregroundStyle(Theme.muted)}}
          .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
      }.buttonStyle(.plain).contextMenu{menu(session)}
        .accessibilityAction(named:"Rename"){rename(session)}
        .accessibilityAction(named:"Move to group"){moving=session}
        .accessibilityAction(named:"Continue in a new chat"){beginAction(session,deleting:false)}
        .accessibilityAction(named:"Delete chat and branches"){beginAction(session,deleting:true)}
      Menu{menu(session)}label:{Image(systemName:"ellipsis").frame(width:44,height:44).contentShape(Rectangle())}
        .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("Actions for \(session.title)").accessibilityIdentifier("chat-actions-"+session.id)
    }
  }
  private func menu(_ session:ChatSession)->some View{
    Group{
      Button("Rename",systemImage:"pencil"){rename(session)}.disabled(native.connection.state != .ready)
      Button("Move to group",systemImage:"folder"){moving=session}.disabled(!native.groups.ready)
      Button("Continue in a new chat",systemImage:"arrow.triangle.branch"){beginAction(session,deleting:false)}.disabled(native.connection.state != .ready)
      Button("Delete chat and branches",systemImage:"trash",role:.destructive){beginAction(session,deleting:true)}.disabled(native.connection.state != .ready)
    }
  }
  private func rename(_ session:ChatSession){if let review=native.renameReview(session){renaming=NativeRenameRequest(session:session,review:review)}}
  private func beginAction(_ session:ChatSession,deleting:Bool){if let target=native.actionTarget(session){action=NativeChatActionRequest(session:session,target:target,deleting:deleting)}}
}
struct NativeChatLocationView:View{
  @Bindable var native:NativeAppCoordinator
  let request:NativeChatLocationRequest
  var onOpen:(()->Void)?
  @Environment(\.dismiss) private var dismiss
  var body:some View{
    NavigationStack{
      List{
        Section{Text("Choose the existing location for your new chat.")}
        ForEach(Array(request.directories.enumerated()),id:\.offset){_,directory in
          Button(directory){Task{
            guard native.projectKey==request.scope else{return}
            await native.createChat(directory:directory,onCreated:{dismiss();onOpen?()})
          }}.disabled(native.creation.busy || native.projectKey != request.scope)
        }
      }.navigationTitle("New chat location").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
    }
  }
}
struct NativeChatSearchView:View{
  @Bindable var native:NativeAppCoordinator
  var onOpen:(()->Void)?
  @State private var query=""
  var body:some View{
    List{
      Section{Text("Searches chat titles on this computer, including older pages. Message contents are not searched.").font(.caption).foregroundStyle(Theme.muted)}
      ForEach(native.search.results){row in
        Button(row.title ?? "Untitled chat"){Task{
          guard native.projectKey==native.search.scope else{return}
          native.navigation.acceptChat(row);onOpen?();await native.open(row)
        }}.frame(minHeight:44).accessibilityIdentifier("native-search-hit-"+row.id)
      }
      if native.search.loading{ProgressView("Searching titles…")}
      if let notice=native.search.notice{Text(notice).font(.callout)}
      if native.search.cursor != nil{Button("Load more matches"){Task{await native.search.more()}}.disabled(native.search.loading)}
      if native.search.complete,native.search.results.isEmpty{Text("No matching chat titles.")}
    }.searchable(text:$query,prompt:"Search all chat titles").navigationTitle("Search chat titles")
      .task(id:query){await native.search.search(query)}.onDisappear{native.search.cancel()}.onChange(of:native.projectKey){_,_ in query=""}
  }
}
