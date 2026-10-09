import SwiftUI
import OpenWorkRemoteCore

struct ChangesView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  private var store: ChangeStore {model.changes}
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:24) {
          Text("Review only").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
          Text("See what changed.").font(.largeTitle.weight(.semibold))
          Text("Includes edits made outside this chat. Review only; files stay on your computer.").foregroundStyle(Theme.muted)
            .accessibilityIdentifier("changes-provenance")
          if store.loading,store.catalog == nil {
            ForEach(0..<3) {_ in RoundedRectangle(cornerRadius:18).fill(Theme.surface).frame(height:70).accessibilityHidden(true)}
            ProgressView().accessibilityLabel("Checking workspace changes")
          }
          if model.connection != .ready {Text("Reconnect to check changes on your computer.").foregroundStyle(Theme.muted)}
          else if store.availability == .needsHostGrant(.fileTransfer) {
            Label("File access is not allowed for this phone. Allow file transfer in Remote access on your computer.",systemImage:"lock").foregroundStyle(Theme.muted)
          } else if !store.loading,store.availability == .unsupported {
            Text("Changes are unavailable on this connection. Update OpenWork Remote on your computer, or review changes there.").foregroundStyle(Theme.muted)
          }
          if let catalog=store.catalog {
            if let reason=catalog.unavailableReason {
              Text(handoff(reason)).foregroundStyle(Theme.muted)
            } else if catalog.files.isEmpty {
              Text("No workspace changes were found.").foregroundStyle(Theme.muted)
            }
            if let context=model.changeContext,store.context == context {
              VStack(spacing:16) {
                ForEach(catalog.files) {ref in
                  NavigationLink {DiffView(ref:ref,context:context)} label: {
                    VStack(alignment:.leading,spacing:8) {
                      HStack {Text(ref.pathLabel).font(.headline).multilineTextAlignment(.leading);Spacer();Image(systemName:"chevron.right").foregroundStyle(Theme.muted)}
                      HStack {
                        Text(status(ref.status))
                        if ref.binary {Text("Binary file")}
                        else {Text("\(ref.added ?? 0) added, \(ref.removed ?? 0) removed")}
                      }.font(.callout).foregroundStyle(Theme.muted)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(20)
                      .background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
                      .overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
                  }.foregroundStyle(Theme.ink).disabled(store.needsRefresh || store.loading)
                    .accessibilityIdentifier("change-row-"+ref.id)
                }
              }
            }
            if catalog.moreOnComputer {Label("More changes are available on your computer.",systemImage:"desktopcomputer").foregroundStyle(Theme.muted)}
          }
          if let notice=store.notice {Text(notice).foregroundStyle(Theme.muted).accessibilityIdentifier("changes-notice")}
          Button("Refresh changes") {Task {await model.refreshChanges()}}
            .frame(minHeight:44).disabled(store.loading || model.connection != .ready)
            .accessibilityIdentifier("changes-refresh")
        }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).foregroundStyle(Theme.ink)
        .navigationTitle("Workspace changes").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.confirmationAction) {Button("Done") {store.close();dismiss()}.accessibilityIdentifier("changes-done")}}
        .task(id:model.changeRefreshID) {await model.refreshChanges()}
    }
  }
  private func handoff(_ reason: ChangeSet.UnavailableReason) -> String {
    switch reason {
    case .nonGit: "This project has no Git change history. Review its files in OpenWork on your computer."
    case .noBaseline: "This project needs its first Git commit before changes can be compared. Continue on your computer."
    case .unsupported: "This project's changes cannot be safely reviewed here. Continue on your computer."
    }
  }
  private func status(_ value: ChangeRef.Status) -> String {
    switch value {case .added:"Added";case .modified:"Modified";case .deleted:"Deleted";case .renamed:"Renamed";case .typeChanged:"Type changed"}
  }
}
