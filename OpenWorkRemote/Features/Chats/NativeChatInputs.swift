import SwiftUI
import OpenWorkRemoteCore

private struct NativeInputPresentation:Identifiable {
  let id=UUID()
  let input:Input
  enum Input {case approval(NativeApprovalContext,OpenCodePermissionRequest),form(NativeFormContext,String)}
}
/// Required inputs are observed separately from optional catalog and history reads.
struct NativeChatInputs:View {
  let native:NativeAppCoordinator
  @State private var presented:NativeInputPresentation?
  var body:some View {
    VStack(spacing:10){
      if let request=native.approvals.requests.first,let context=native.approvals.context{
        Button{presented=NativeInputPresentation(input:.approval(context,request))}label:{
          inputRow("Approval needed",request.action,icon:"hand.raised")
        }.accessibilityIdentifier("native-approval-open")
      }
      if let form=native.forms.pending.first,let context=native.forms.context{
        Button{presented=NativeInputPresentation(input:.form(context,form.id))}label:{
          inputRow("OpenCode has a question",form.title,icon:"questionmark.bubble")
        }.accessibilityIdentifier("native-form-open")
      }
      if native.approvals.issue != nil || native.forms.issue == .unavailable{
        Label("Required inputs could not be checked. Check the connection or continue on your computer.",systemImage:"exclamationmark.circle")
          .font(.callout).foregroundStyle(Theme.muted)
      }
      if let issue=native.conversation.issue{
        Label(message(issue),systemImage:"exclamationmark.circle").font(.callout).foregroundStyle(Theme.muted)
      }
    }.padding(.horizontal,24).padding(.top,10)
      .sheet(item:$presented){item in
        switch item.input{
        case let .approval(context,request):NativeApprovalSheet(store:native.approvals,context:context,request:request)
        case let .form(context,id):NativeFormSheet(store:native.forms,context:context,formID:id).nativeSharingReview(native,operation:.formAnswer)
        }
      }
  }
  private func inputRow(_ title:String,_ detail:String,icon:String)->some View{
    HStack(spacing:12){Image(systemName:icon);VStack(alignment:.leading,spacing:4){Text(title).font(.callout.weight(.semibold));Text(detail).font(.caption).lineLimit(2)};Spacer();Image(systemName:"chevron.right")}
      .foregroundStyle(Theme.ink).padding(16).frame(maxWidth:.infinity,minHeight:52,alignment:.leading)
      .background(Theme.surface,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
  }
  private func message(_ issue:NativeConversationIssue)->String{
    switch issue{
    case .authenticationRequired:return "OpenCode rejected this connection. Pair again with a fresh code."
    case .incompatible:return "This OpenCode version needs compatibility testing before sending."
    case .locationChanged:return "This chat moved. Reopen it from Your Chats."
    case .storage:return "Your draft could not be saved. Unlock this device and try again."
    case .unknownSend,.conflictingSend:return "Delivery could not be confirmed. Check the conversation before trying again."
    case .sendRejected:return "The message was not submitted. Review the draft and connection before trying again."
    case .stopOutcomeUnknown:return "Stop could not be confirmed. Check this chat on your computer."
    case .unavailable:return "The latest replies could not be loaded. Reconnect or try again."
    }
  }
}
