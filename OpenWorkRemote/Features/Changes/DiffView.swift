import SwiftUI
import OpenWorkRemoteCore

struct DiffView: View {
  let ref: ChangeRef
  let context: ChangeContext
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var page=0
  private var store: ChangeStore {model.changes}
  private var pageCount: Int {max(1,(store.lines.count+199)/200)}
  private var visible: ArraySlice<DiffLine> {store.lines.dropFirst(page*200).prefix(200)}
  var body: some View {
    ScrollView {
      VStack(alignment:.leading,spacing:20) {
        Text(ref.pathLabel).font(.title2.weight(.semibold)).textSelection(.enabled)
        Text("Workspace changes include edits made outside this chat.").font(.callout).foregroundStyle(Theme.muted)
        if store.context != context {Text("Refresh workspace changes to open this file again.").foregroundStyle(Theme.muted)}
        if store.opening != nil {ProgressView().accessibilityLabel("Checking this diff")}
        if let diff=store.diff,diff.changeId == ref.id,store.context == context {
          if diff.binary {Text("Binary file. Review this change on your computer.").foregroundStyle(Theme.muted)}
          else if diff.text.isEmpty {Text("No text lines changed.").foregroundStyle(Theme.muted)}
          else {
            VStack(alignment:.leading,spacing:4) {
              ForEach(visible) {line in
                Text(line.text.isEmpty ? " " : line.text).font(.system(.callout,design:.monospaced))
                  .foregroundStyle(Theme.ink).textSelection(.enabled)
                  .frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,3).padding(.horizontal,8)
                  .background(line.kind == .addition ? Theme.diffAdded : line.kind == .removal ? Theme.diffRemoved : Color.clear,in:RoundedRectangle(cornerRadius:6))
                  .accessibilityLabel(accessibility(line))
                  .accessibilityIdentifier("diff-line-\(line.id)")
              }
            }.padding(12).background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
              .overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
            if visible.contains(where:{$0.shortened}) {Text("Long lines are shortened here. Read the full lines on your computer.").font(.callout).foregroundStyle(Theme.muted)}

          }
          if diff.omitted {Label("Part of this diff is omitted. Review the full change on your computer.",systemImage:"desktopcomputer").font(.callout).foregroundStyle(Theme.muted)}
        }
        if store.availability == .needsHostGrant(.fileTransfer) {Text("File access is no longer allowed. Continue on your computer.").foregroundStyle(Theme.muted)}
        if let notice=store.notice {
          Text(notice).foregroundStyle(Theme.muted)
          Button("Refresh changes") {dismiss();Task {await model.refreshChanges()}}
            .disabled(store.loading || model.connection != .ready).accessibilityIdentifier("diff-refresh")
        }
      }.padding(24).frame(maxWidth:700,alignment:.leading).frame(maxWidth:.infinity)
    }.background(Theme.background).foregroundStyle(Theme.ink)
      .navigationTitle("Review change").navigationBarTitleDisplayMode(.inline)
      .toolbar {ToolbarItemGroup(placement:.bottomBar) {
        if pageCount > 1 {
          Button("Previous lines") {page=max(0,page-1)}.disabled(page == 0)
          Spacer();Text("\(page+1) of \(pageCount)").font(.caption).foregroundStyle(Theme.muted);Spacer()
          Button("Next lines") {page=min(pageCount-1,page+1)}.disabled(page+1 == pageCount)
        }
      }}
      .task(id:context) {page=0;await model.openDiff(ref,context:context)}
      .onDisappear {store.closeDiff()}
  }
  private func accessibility(_ line: DiffLine) -> String {
    let prefix: String
    switch line.kind {case .addition:prefix="Added line";case .removal:prefix="Removed line";case .header:prefix="Diff heading";case .context:prefix="Unchanged line"}
    return prefix+": "+line.text+(line.shortened ? ", shortened; continue on your computer" : "")
  }
}
