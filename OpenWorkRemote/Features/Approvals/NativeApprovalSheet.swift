import SwiftUI
import OpenWorkRemoteCore

struct NativeApprovalSheet:View {
  let store:NativeApprovalStore
  let context:NativeApprovalContext
  let request:OpenCodePermissionRequest
  @Environment(\.dismiss) private var dismiss
  @State private var reviewAlways=false
  private var pending:Bool{store.context==context && store.requests.contains(request)}
  var body:some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:24){
          Text("OpenCode needs your approval").font(.largeTitle.bold())
          Text(request.action).font(.title2.bold())
          if let message=request.message{Text(message)}
          ForEach(Array(request.resources.enumerated()),id:\.offset){_,resource in
            Text(resource).font(.body.monospaced()).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
          }
          Text("Applies to this request in the selected chat. Review the resource before allowing it.").font(.callout).foregroundStyle(Theme.muted)
          if let issue=store.issue {
            Text(issueText(issue)).font(.callout).foregroundStyle(Theme.muted)
            if issue != .allowReviewRequired{Button("Check request status"){Task{await store.refresh(context)}}}
          }
          if !pending{Text("This request is no longer pending. It may have been answered on the computer.").accessibilityIdentifier("native-approval-resolved")}
          HStack{if store.replying{ProgressView("Checking with computer…")}}
          Button("Allow once"){reply(.once)}.buttonStyle(PrimaryButtonStyle()).disabled(!pending || store.replying || store.loading)
          if request.save?.isEmpty == false{
            Button("Always allow…"){reviewAlways=true}.frame(minHeight:44).disabled(!pending || store.replying || store.loading)
          }
          Button("Deny",role:.destructive){reply(.reject)}.frame(minHeight:44).disabled(!pending || store.replying || store.loading)
        }.padding(24).frame(maxWidth:620)
      }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle("Tool approval").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}
    }.sheet(isPresented:$reviewAlways){
      NativeAllowReview(title:"Remember this allowance?",details:(request.save ?? []).map{request.action+"\n"+$0},explanation:"OpenCode will remember these resource patterns for this project, including other chats. A pattern can cover more than the current request. Computer-side policies and explicit denials still apply."){
        reviewAlways=false;reply(.always,reviewed:true)
      }
    }
  }
  private func reply(_ decision:OpenCodePermissionDecision,reviewed:Bool=false){
    Task{if await store.reply(request,decision:decision,context:context,allowReviewed:reviewed){dismiss()}}
  }
  private func issueText(_ issue:NativeApprovalIssue)->String{
    switch issue{
    case .allowReviewRequired:return "Review the exact remembered patterns before choosing Always allow."
    case .authenticationRequired:return "Pair again with a fresh OpenCode code from the computer."
    case .unavailable:return "The current request status could not be loaded. Check the connection."
    case .replyUnconfirmed:return "Your answer could not be confirmed. Check status before taking another action."
    }
  }
}
