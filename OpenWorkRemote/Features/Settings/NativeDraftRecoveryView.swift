import SwiftUI
import OpenWorkRemoteCore

struct NativeDraftRecoveryView:View{
  let native:NativeAppCoordinator
  let migration:ConnectionMigration?
  @State private var selected:NativeDraftRecovery?
  @State private var copiedEarlier=false
  var body:some View{
    List{
      Section{
        Text("Saved text stays separate from your current connection and folder. Open a draft to copy its text deliberately. Files, skills and unconfirmed sends are never transferred with it.")
          .font(.callout).foregroundStyle(Theme.muted)
      }
      if let text=migration?.recoverableText{
        Section("Earlier OpenWork beta"){
          Text("Your earlier chats remain in OpenWork. This copies only saved draft text to the clipboard.").font(.callout).foregroundStyle(Theme.muted)
          Button(copiedEarlier ? "Earlier text copied":"Copy earlier OpenWork text"){UIPasteboard.general.string=text;copiedEarlier=true}
            .frame(minHeight:44).accessibilityIdentifier("native-recover-legacy-copy")
        }
      }
      Section("Saved PocketWork text"){
        if native.journal.recoverableDrafts.isEmpty{Text("No saved draft text.").foregroundStyle(Theme.muted)}
        ForEach(native.journal.recoverableDrafts){draft in
          Button{selected=draft}label:{
            VStack(alignment:.leading,spacing:6){
              switch draft.id{
              case .scoped(let target):
                Text("Saved chat").font(.headline)
                Text(verbatim:target.directory).font(.caption.monospaced()).foregroundStyle(Theme.muted)
                Text(verbatim:target.sessionID).font(.caption).foregroundStyle(Theme.muted)
              case .earlier(let key):
                Text("Earlier preview draft").font(.headline)
                Text(verbatim:key.sessionId).font(.caption).foregroundStyle(Theme.muted)
                Text("Its original folder was not recorded.").font(.caption).foregroundStyle(Theme.muted)
              }
              Text(verbatim:draft.text).lineLimit(2).font(.callout)
            }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
          }.privacySensitive()
        }
      }
    }.navigationTitle("Draft recovery").scrollContentBackground(.hidden).background(Theme.background)
      .sheet(item:$selected){draft in NativeDraftRecoveryDetail(native:native,draft:draft)}
  }
}
private struct NativeDraftRecoveryDetail:View{
  let native:NativeAppCoordinator
  let draft:NativeDraftRecovery
  @Environment(\.dismiss) private var dismiss
  @State private var copied=false
  @State private var review:CopyReview?
  @State private var notice:String?
  private struct CopyReview{let target:OpenCodeTarget;let expectedText:String}
  private var target:OpenCodeTarget?{
    guard native.connection.state == .ready,native.conversation.currentSession != nil,
      native.conversation.target==native.navigation.target else{return nil}
    return native.navigation.target
  }
  var body:some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:20){
          Text(verbatim:draft.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).privacySensitive()
          Button(copied ? "Text copied":"Copy text"){UIPasteboard.general.string=draft.text;copied=true}.frame(minHeight:44)
          if let target{
            Text("Current destination").font(.headline)
            Text(verbatim:target.directory).font(.callout.monospaced()).foregroundStyle(Theme.muted)
            Text(verbatim:target.sessionID).font(.caption).foregroundStyle(Theme.muted)
            Button("Copy into current draft"){
              review=CopyReview(target:target,expectedText:native.journal.draft(for:target))
            }.buttonStyle(PrimaryButtonStyle()).disabled(native.journal.pending(for:target) != nil)
          }else{Text("Open a connected chat before copying into a draft. Clipboard copying remains available.").font(.callout).foregroundStyle(Theme.muted)}
          Text("The original recovery text is kept. Nothing is sent.").font(.footnote).foregroundStyle(Theme.muted)
          if let notice{Text(notice).font(.callout).foregroundStyle(Theme.muted)}
        }.padding(24).frame(maxWidth:620,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).navigationTitle("Saved draft").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}.frame(minHeight:44)}}
        .confirmationDialog("Replace the current unsent draft with this saved text?",isPresented:Binding(get:{review != nil},set:{if !$0{review=nil}}),titleVisibility:.visible){
          Button("Copy into this draft"){
            guard let captured=review else{return};review=nil
            Task{
              guard target==captured.target else{notice="The current chat changed. Review the destination again.";return}
              do{try await native.journal.copyRecoveredDraft(draft,to:captured.target,expectedDraft:captured.expectedText);notice="Text copied into the current draft. Review it before sending."}
              catch{notice="The draft or saved text changed, or storage is unavailable. Review the destination and try again."}
            }
          }
          Button("Cancel",role:.cancel){review=nil}
        }message:{if let review{Text(review.target.directory+"\n"+review.target.sessionID+"\nThe existing unsent text in this chat will be replaced.")}}
    }
  }
}
