import OpenWorkRemoteCore
import SwiftUI
import UIKit

struct NativeGroupNameRequest:Identifiable{
  let id=UUID()
  let group:LocalChatGroup?
  let scope:NativeProjectKey
  let revision:UInt64
}
struct NativeGroupEditor:View{
  @Bindable var native:NativeAppCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var naming:NativeGroupNameRequest?
  @State private var removing:LocalChatGroup?
  @State private var error:String?
  static var localLabel:String{UIDevice.current.userInterfaceIdiom == .pad ? "On this iPad":"On this iPhone"}
  var body:some View{
    NavigationStack{
      List{
        Section{
          Text(Self.localLabel+". Group changes stay on this device. Removing a group keeps all chats.").font(.callout).foregroundStyle(Theme.muted)
        }
        Section{
          ForEach(native.groups.snapshot.groups){group in
            HStack{Text(group.label);Spacer();Menu{
              Button("Rename",systemImage:"pencil"){name(group)}
              Button("Remove group",systemImage:"trash",role:.destructive){removing=group}
            }label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.accessibilityLabel("Actions for group "+group.label)}
          }.onMove{from,to in
            var ids=native.groups.snapshot.groups.map(\.id);ids.move(fromOffsets:from,toOffset:to)
            change(.reorder(ids))
          }
          Button("New group",systemImage:"folder.badge.plus"){name(nil)}.disabled(!native.groups.ready || native.groups.busy).accessibilityIdentifier("native-group-new")
        }header:{Text("Groups")}
        if let error{Text(error).foregroundStyle(.red)}
      }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Manage groups")
        .toolbar{
          ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}.accessibilityIdentifier("native-groups-done")} 
          ToolbarItem(placement:.primaryAction){EditButton().disabled(native.groups.busy)}
        }.sheet(item:$naming){NativeGroupNameView(native:native,request:$0)}
        .confirmationDialog("Remove this group? Chats will stay.",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}})){
          if let removing{Button("Remove “\(removing.label)”",role:.destructive){change(.remove(removing.id));self.removing=nil}}
          Button("Cancel",role:.cancel){removing=nil}
        }
    }
  }
  private func name(_ group:LocalChatGroup?){if let scope=native.groups.scope{naming=NativeGroupNameRequest(group:group,scope:scope,revision:native.groups.snapshot.revision)}}
  private func change(_ action:LocalGroupAction){
    guard let scope=native.groups.scope else{return};let revision=native.groups.snapshot.revision
    Task{do{try await native.groups.change(action,scope:scope,expectedRevision:revision)}catch{self.error="The groups changed or could not be saved. Reopen this screen and try again."}}
  }
}
struct NativeGroupNameView:View{
  @Bindable var native:NativeAppCoordinator
  let request:NativeGroupNameRequest
  @Environment(\.dismiss) private var dismiss
  @State private var name:String
  @State private var error:String?
  @State private var saving=false
  init(native:NativeAppCoordinator,request:NativeGroupNameRequest){self.native=native;self.request=request;_name=State(initialValue:request.group?.label ?? "")}
  var body:some View{
    NavigationStack{
      Form{
        TextField("Group name",text:$name).accessibilityIdentifier("native-group-name")
        Text(NativeGroupEditor.localLabel+". This does not rename a project on your computer.").font(.caption)
        if let error{Text(error).foregroundStyle(.red)}
      }.navigationTitle(request.group==nil ? "New group":"Rename group").toolbar{
        ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
        ToolbarItem(placement:.confirmationAction){Button("Save"){Task{
          saving=true;defer{saving=false}
          do{
            let action:LocalGroupAction=request.group.map{.rename($0.id,name)} ?? .create(name)
            try await native.groups.change(action,scope:request.scope,expectedRevision:request.revision);dismiss()
          }catch{self.error="The group could not be saved. Use a short name, or reopen this screen if groups changed."}
        }}.disabled(saving || (try? SessionGroup.label(name))==nil).accessibilityIdentifier("native-group-save")}
      }
    }
  }
}
struct NativeMoveChatView:View{
  @Bindable var native:NativeAppCoordinator
  let session:ChatSession
  @Environment(\.dismiss) private var dismiss
  @State private var scope:NativeProjectKey?
  @State private var revision:UInt64?
  @State private var error:String?
  var body:some View{
    NavigationStack{
      List{
        Section{Text(NativeGroupEditor.localLabel+". Your chat stays in the same OpenCode project.").font(.callout)}
        Button("No group"){assign(nil)}
        ForEach(native.groups.snapshot.groups){group in Button(group.label){assign(group.id)}.accessibilityIdentifier("native-move-choice-"+group.id.uuidString)}
        if let error{Text(error).foregroundStyle(.red)}
      }.navigationTitle("Move to group").toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}}}
        .onAppear{scope=native.groups.scope;revision=native.groups.snapshot.revision}
    }
  }
  private func assign(_ id:UUID?){
    guard let scope,let revision,scope.projectID==session.workspaceId else{return}
    Task{do{try await native.groups.change(.assign(sessionID:session.id,groupID:id),scope:scope,expectedRevision:revision);dismiss()}catch{self.error="Groups changed or could not be saved. Reopen Move to group and try again."}}
  }
}
