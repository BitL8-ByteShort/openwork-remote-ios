import SwiftUI
import OpenWorkRemoteCore

struct NativeChangesView:View{
  let native:NativeAppCoordinator
  @Environment(\.dismiss) private var dismiss
  private var store:NativeWorkspaceStore{native.workspace}
  var body:some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:22){
          Text("Review only").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
          Text("See what changed.").font(.largeTitle.weight(.semibold))
          Text("Working-copy changes can include edits made outside this chat. Opening a diff retrieves the computer’s current working-copy diff, which may include other files.").font(.callout).foregroundStyle(Theme.muted)
          if let context=store.context{
            Text(context.target.directory).font(.caption.monospaced()).foregroundStyle(Theme.muted).textSelection(.enabled)
            if store.changesLoading{ProgressView("Checking working-copy changes…")}
            if let info=store.info{
              if info.provider==nil{Text("This location has no native version-control provider. Review its files on your computer.")}
              else{
                Text((info.provider ?? "Version control")+(info.branch.current.map{" · "+$0} ?? "")).font(.caption).foregroundStyle(Theme.muted)
                if store.changes.isEmpty,!store.changesLoading{Text("No working-copy changes were reported.")}
                ForEach(store.changes){file in
                  NavigationLink{NativeDiffView(store:store,context:context,file:file)}label:{
                    VStack(alignment:.leading,spacing:8){Text(file.file).font(.headline).multilineTextAlignment(.leading);Text("\(file.status.rawValue.capitalized) · \(file.additions) added, \(file.deletions) removed").font(.callout).foregroundStyle(Theme.muted)}
                      .frame(maxWidth:.infinity,alignment:.leading).padding(20).background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
                  }.foregroundStyle(Theme.ink).disabled(store.changesLoading || store.changesNotice != nil).accessibilityIdentifier("native-change-"+file.file)
                }
              }
            }
            if let notice=store.changesNotice{Text(notice).foregroundStyle(Theme.muted)}
            Button("Refresh changes"){Task{await store.loadChanges(context)}}.frame(minHeight:44).disabled(store.changesLoading)
          }else{Text("Open a connected chat to review changes in its computer location.")}
        }.padding(24).frame(maxWidth:700,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).navigationTitle("Working-copy changes").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){store.closeDiff();dismiss()}.accessibilityIdentifier("native-changes-done")}}
    }.task(id:store.context){if let context=store.context{await store.loadChanges(context)}}
  }
}
private struct NativeDiffView:View{
  let store:NativeWorkspaceStore
  let context:NativeWorkspaceContext
  let file:OpenCodeChange
  @State private var page=0
  private var pageCount:Int{max(1,(store.diffLines.count+199)/200)}
  private var visible:ArraySlice<DiffLine>{store.diffLines.dropFirst(page*200).prefix(200)}
  var body:some View{
    ScrollView{
      VStack(alignment:.leading,spacing:20){
        Text(file.file).font(.title2.weight(.semibold)).textSelection(.enabled)
        Text("Current native working-copy diff. Files stay on your computer; this screen cannot stage, commit or revert changes.").font(.caption).foregroundStyle(Theme.muted)
        if store.context != context{Text("The chat changed. Reopen Working-copy changes.")}
        if store.diffLoading{ProgressView("Reading native diff…")}
        if let diff=store.diff,store.context==context{
          if diff.patch.isEmpty{Text("OpenCode returned no text patch. Binary, untracked or unsupported changes may need review on your computer.")}
          else{VStack(alignment:.leading,spacing:4){
            ForEach(visible){line in
              Text(line.text.isEmpty ? " ":line.text).font(.system(.callout,design:.monospaced)).textSelection(.enabled)
                .frame(maxWidth:.infinity,alignment:.leading).padding(6)
                .background(line.kind == .addition ? Theme.diffAdded:line.kind == .removal ? Theme.diffRemoved:Color.clear)
                .accessibilityLabel((line.kind == .addition ? "Added line: ":line.kind == .removal ? "Removed line: ":"Diff line: ")+line.text)
            }
          }}
          if store.diffOmitted || visible.contains(where:{$0.shortened}){Text("Part of this diff is shortened here. Review the complete change on your computer.").font(.caption).foregroundStyle(Theme.muted)}
        }
        if let notice=store.changesNotice{Text(notice).foregroundStyle(Theme.muted)}
      }.padding(24).frame(maxWidth:800,alignment:.leading).frame(maxWidth:.infinity)
    }.background(Theme.background).navigationTitle("Review change").navigationBarTitleDisplayMode(.inline)
      .toolbar{ToolbarItemGroup(placement:.bottomBar){if pageCount>1{
        Button("Previous lines"){page=max(0,page-1)}.disabled(page==0);Spacer();Text("\(page+1) of \(pageCount)").font(.caption);Spacer();Button("Next lines"){page=min(pageCount-1,page+1)}.disabled(page+1==pageCount)
      }}}
      .task(id:context){page=0;await store.openDiff(file,context:context)}.onDisappear{store.closeDiff()}
  }
}
