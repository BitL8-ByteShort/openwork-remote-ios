import SwiftUI
import OpenWorkRemoteCore

private struct ArtifactShareFile: Identifiable {
  let id = UUID()
  let url: URL
}
struct ArtifactPreview: View {
  let ref: ArtifactRef
  let context: ArtifactContext
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var sharing = false
  @State private var share: ArtifactShareFile?
  #if DEBUG && targetEnvironment(simulator)
  @State private var testSaved: String?
  #endif
  private var store: ArtifactStore { model.artifacts }
  private var matches: Bool { model.artifactContext == context && store.context == context }
  var body: some View {
    ScrollView {
      VStack(alignment:.leading,spacing:24) {
        Text("FROM THIS CHAT").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        Text(ref.name).font(.title.weight(.semibold)).textSelection(.enabled)
        Text("\(ByteCountFormatter.string(fromByteCount:Int64(ref.bytes),countStyle:.file)) · \(model.host?.displayName ?? "Your computer")\nPreview a temporary copy downloaded from your computer.")
          .foregroundStyle(Theme.muted)
        if !matches {
          Text("This chat or connection changed. Open the file again from your current chat.").foregroundStyle(Theme.muted)
        } else if store.downloading != nil {
          ProgressView(value:Double(store.receivedBytes),total:Double(ref.bytes)) { Text("Downloading…") }
          Button("Cancel download") { store.closePreview(); dismiss() }.frame(minHeight:44)
        } else if let preview = store.preview, store.ready?.ref == ref {
          if let text = preview.text {
            Text(text).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(20)
              .background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
          } else if let url = preview.imageURL, let image = UIImage(contentsOfFile:url.path) {
            Image(uiImage:image).resizable().scaledToFit().accessibilityLabel(ref.previewKind == .pdf ? "PDF page \(preview.page) of \(preview.pageCount)" : "Preview of \(ref.name)")
              .clipShape(RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
          } else {
            Label("This document can be shared or saved without a preview.",systemImage:"doc").foregroundStyle(Theme.muted)
          }
          if preview.truncated {
            Text("The preview shows part of this text. Sharing exports the complete downloaded file.").font(.callout).foregroundStyle(Theme.muted)
          }
          if preview.pageCount > 1 {
            HStack {
              Button("Previous page") { Task { await store.showPage(preview.page-1,context:context) } }
                .disabled(preview.page <= 1).frame(minHeight:44)
              Spacer();Text("\(preview.page) / \(preview.pageCount)").font(.caption)
              Spacer();Button("Next page") { Task { await store.showPage(preview.page+1,context:context) } }
                .disabled(preview.page >= preview.pageCount).frame(minHeight:44)
            }
          }
        }
        if matches, let notice = store.notice { Text(notice).font(.callout).foregroundStyle(Theme.muted) }
        #if DEBUG && targetEnvironment(simulator)
        if let testSaved { Text("Test copy saved: \(testSaved)") }
        #endif
        Text("Only this file will be shared. Choose where it goes in the iOS share sheet.").font(.callout).foregroundStyle(Theme.muted)
        Button {
          sharing = true
          Task {
            let url = await model.shareArtifact(context:context)
            if matches, let url { share = ArtifactShareFile(url:url) }
            sharing = false
          }
        } label: {
          HStack { if sharing { ProgressView().tint(.white) };Text("Share or save a copy") }.frame(maxWidth:.infinity)
        }.buttonStyle(PrimaryButtonStyle()).disabled(!matches || !store.canShare || sharing || store.ready?.ref != ref)
      }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
    }.background(Theme.background).foregroundStyle(Theme.ink).navigationTitle("Preview file").navigationBarTitleDisplayMode(.inline)
      .task { await model.downloadArtifact(ref,context:context) }
      // The activity controller may cover this view while reading its item.
      // Its copy must survive presentation; leaving the preview still cleans up.
      .onDisappear { if share == nil { store.closePreview() } }
      .onChange(of:model.artifactContext) { _, value in if value != context { share = nil } }
      .sheet(item:$share) { file in
        #if DEBUG && targetEnvironment(simulator)
        ArtifactShareSheet(url:file.url,completion:{ share = nil },testSaved:{ testSaved = $0 })
        #else
        ArtifactShareSheet(url:file.url,completion:{ share = nil })
        #endif
      }
  }
}
