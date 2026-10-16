import SwiftUI

struct NativeConnectionSettingsView:View {
  let native:NativeAppCoordinator
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @AppStorage("appearance") private var appearance="system"
  @AppStorage("compactToolActivity") private var compact=true
  @State private var modelSettings=false
  @State private var forget=false
  @State private var newDefaults:NativeDefaultsPresentation?
  var body:some View{
    NavigationStack{
      List{
        Section{
          HStack(spacing:14){Image(systemName:"desktopcomputer").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment:.leading,spacing:5){Text(model.computerName).font(.headline);Text(model.connectionLabel).font(.caption).foregroundStyle(Theme.muted)}}.padding(.vertical,8)
          if let version=native.connection.serverVersion{LabeledContent("OpenCode",value:version)}
          if let origin=native.connection.connection?.origin{Text(origin.absoluteString).font(.caption.monospaced()).textSelection(.enabled)}
          Button(model.connection == .revoked ? "Pair again" : "Reconnect"){model.connect()}
          Button("Pair again"){dismiss();native.connection.pairAgain()}
            .disabled(native.connection.isBusy).accessibilityIdentifier("native-pair-again")
        }header:{Text("Paired computer")}footer:{Text("Use a fresh code if OpenCode’s address changed. Your saved connection stays until pairing succeeds.")}
        Section{
          NavigationLink("Visible projects"){NativeProjectVisibilityView(native:native)}
        }footer:{Text("Project visibility changes this device’s list. It does not restrict the server access granted by pairing.")}
        Section{
          NavigationLink("Permissions"){PermissionsView()}
          Button("Model & settings"){modelSettings=true}.disabled(!model.canChooseModel)
          Toggle("Compact tool activity",isOn:$compact)
        }header:{Text("Conversation")}footer:{Text("Group tool calls into an expandable Activity row. Required approvals and questions stay visible.")}
        Section{Button("New chat defaults"){if let scope=native.projectKey{newDefaults=NativeDefaultsPresentation(scope:scope,value:native.defaults.value,locations:native.newChatLocations)}}.disabled(native.projectKey==nil).accessibilityIdentifier("native-defaults-open")}
        Section{Picker("Appearance",selection:$appearance){Text("System").tag("system");Text("Light").tag("light");Text("Dark").tag("dark")}}
        Section{NavigationLink("Data Controls"){DataControlsView()}.accessibilityIdentifier("native-local-data-open")}
        Section{NavigationLink("About & Help"){AboutView()}.accessibilityIdentifier("settings-about")}
        Section{
          Text("Keep OpenCode running with its built-in Remote access enabled. Replies continue on the computer while PocketWork is closed.")
          Text("Forgetting removes this device’s credential. OpenCode v2 does not offer individual device revocation. Rotate the server password on your computer to invalidate all paired devices.")
        }.font(.callout).foregroundStyle(Theme.muted)
        Section{Button("Forget this computer",role:.destructive){forget=true}}footer:{Text("Saved drafts stay on this device, separated by connection and chat.")}
      }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}.accessibilityIdentifier("native-connection-done")}}
        .sheet(isPresented:$modelSettings){ModelSettingsView()}
        .sheet(item:$newDefaults){NativeChatDefaultsView(native:native,review:$0)}
        .confirmationDialog("Forget this computer?",isPresented:$forget,titleVisibility:.visible){
          Button("Forget computer",role:.destructive){Task{await model.forget();if model.connection == .unpaired{dismiss()}}}
        }message:{Text("This removes the saved connection on this device. It does not revoke the server token or delete chats or files on the computer.")}
    }
  }
}
struct NativeProjectVisibilityView:View{
  let native:NativeAppCoordinator
  var body:some View{
    Form{
      Section{
        Toggle("Show future projects",isOn:Binding(get:{native.visibility.policy.showNewProjects},set:{value in Task{try? await native.visibility.setShowNewProjects(value)}}))
        ForEach(native.navigation.projects){project in
          Toggle(project.name ?? project.canonical,isOn:Binding(get:{native.visibility.policy.shows(project.id)},set:{value in Task{try? await native.visibility.setShown(project.id,shown:value)}}))
            .accessibilityIdentifier("native-project-visible-"+project.id)
        }
      }header:{Text("On this device")}footer:{Text("Hidden projects remain accessible through the paired server. This is a local display preference, not a permission boundary.")}
      if let error=native.visibility.lastError{Section{Text(error).foregroundStyle(.red)}}
    }.disabled(native.visibility.busy).navigationTitle("Visible projects").scrollContentBackground(.hidden).background(Theme.background)
  }
}
