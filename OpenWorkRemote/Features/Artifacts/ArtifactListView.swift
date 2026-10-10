import SwiftUI
import OpenWorkRemoteCore

struct ArtifactListView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  private var store: ArtifactStore { model.artifacts }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:24) {
          Text("RESULTS").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
          Text("Ready to take\nwith you.").font(.largeTitle.weight(.semibold))
          Text("Files stay on your computer. Tap a file to download a temporary preview, or save a copy.")
            .foregroundStyle(Theme.muted)
          if store.loading { ProgressView("Checking files…").frame(maxWidth:.infinity,minHeight:60) }
          else if store.availability == .needsHostGrant(.fileTransfer) {
            Text("File access is not allowed for this phone. Allow file transfer in Remote access on your computer.")
              .foregroundStyle(Theme.muted)
          } else if store.availability == .unsupported {
            Text(store.notice ?? "Files are unavailable on this connection. Update or reconnect to OpenWork Remote on your computer.")
              .foregroundStyle(Theme.muted)
          } else if store.items.isEmpty {
            Text("No files from this chat yet. Supported results will appear here after OpenWork creates them.").foregroundStyle(Theme.muted)
          }
          if let context = model.artifactContext, store.context == context {
            VStack(spacing:16) {
              ForEach(store.items) { ref in
                NavigationLink { ArtifactPreview(ref:ref,context:context) } label: {
                  VStack(alignment:.leading,spacing:10) {
                    HStack {
                      Text(ref.name).font(.headline).multilineTextAlignment(.leading)
                      Spacer();Image(systemName:"chevron.right").foregroundStyle(Theme.muted)
                    }
                    Text("\(ref.previewKind == .shareOnly ? "Document" : ref.previewKind.rawValue.capitalized) · \(ByteCountFormatter.string(fromByteCount:Int64(ref.bytes),countStyle:.file))")
                      .font(.callout).foregroundStyle(Theme.muted)
                  }.frame(maxWidth:.infinity,alignment:.leading).padding(20)
                    .background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
                    .overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
                }.foregroundStyle(Theme.ink).accessibilityIdentifier("artifact-row-"+ref.id)
              }
            }
          }
          if store.moreOnComputer {
            Label("More files are available on your computer. Large or unsupported results stay there.",systemImage:"desktopcomputer")
              .font(.callout).foregroundStyle(Theme.muted)
          }
          Text("Downloads begin when you tap a file. Sharing or saving a copy is a separate action.")
            .font(.callout).foregroundStyle(Theme.muted)
          Button("Refresh files") { Task { await model.refreshArtifacts() } }
            .frame(minHeight:44).disabled(store.loading || model.connection != .ready)
        }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).foregroundStyle(Theme.ink)
        .navigationTitle("Files from this chat").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.confirmationAction) {
          Button("Done") { model.artifacts.closePreview(); dismiss() }.accessibilityIdentifier("artifact-done")
        } }
        .task(id:model.artifactRefreshID) { await model.refreshArtifacts() }
    }
  }
}
