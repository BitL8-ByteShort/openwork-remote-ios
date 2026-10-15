#if !DEBUG
import SwiftUI

// Shared presentation names have native-only shipping implementations. The
// earlier bridge screens are compiled solely for DEBUG historical fixtures.
struct ChatListView: View {
  @Environment(AppModel.self) private var model
  var body: some View { if let native=model.native { NativeChatListView(native:native) } }
}
struct ConnectionView: View {
  @Environment(AppModel.self) private var model
  var body: some View { if let native=model.native { NativeConnectionSettingsView(native:native) } }
}
struct PermissionsView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    if let native=model.native, let context=native.controls.context { NativePermissionsView(store:native.controls,context:context) }
    else { Form { Section { Text("Open a chat to review its tool rules and saved permissions.") }
      Section { Text("Native pairing grants server access. Hiding a project is a display preference on this device.") } }.navigationTitle("Permissions") }
  }
}
struct ArtifactListView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    if let native=model.native, let context=native.results.context { NativeArtifactListView(store:native.results,context:context) }
    else { ContentUnavailableView("Open a chat",systemImage:"doc.on.doc",description:Text("Choose a connected chat to browse its project files.")) }
  }
}
struct ChangesView: View {
  @Environment(AppModel.self) private var model
  var body: some View { if let native=model.native { NativeChangesView(native:native) } }
}
struct ModelSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var files=false
  @State private var changes=false
  var body: some View {
    if let native=model.native, let context=native.controls.context {
      NativeModelSettingsView(store:native.controls,context:context,onFiles:{files=true},onChanges:{changes=true})
        .sheet(isPresented:$files,onDismiss:{native.results.closePreview()}){ArtifactListView()}
        .sheet(isPresented:$changes){ChangesView()}
    } else { NavigationStack { ContentUnavailableView("Open a chat",systemImage:"bubble.left",description:Text("Choose a connected OpenCode chat to change its model and settings."))
      .toolbar { ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}} } } }
  }
}
#endif
