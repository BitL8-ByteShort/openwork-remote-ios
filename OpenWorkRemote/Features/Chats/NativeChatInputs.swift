import SwiftUI
import OpenWorkRemoteCore

private struct NativeInputPresentation:Identifiable {
  let id=UUID()
  let input:Input
  enum Input {case approval(NativeApprovalContext,OpenCodePermissionRequest),form(NativeFormContext,String)}
}
/// Required inputs are observed separately from optional catalog and history reads.
struct NativeChatInputs:View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let native:NativeAppCoordinator
  var compact=false
  @State private var presented:NativeInputPresentation?
  var body:some View {
    VStack(spacing:10){
      if compact{
        if !native.approvals.requests.isEmpty || !native.forms.pending.isEmpty{
          HStack(spacing:12){Text("Input").font(.caption.weight(.medium)).fixedSize();Spacer(minLength:0);inputButtons}
            .padding(12).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
        }
      }else{inputButtons}
      if native.approvals.issue != nil || native.forms.issue == .unavailable{
        Label("Required inputs could not be checked. Check the connection or continue on your computer.",systemImage:"exclamationmark.circle")
          .font(.callout).foregroundStyle(Theme.muted)
      }
      if let issue=native.conversation.issue{
        Label(message(issue),systemImage:"exclamationmark.circle").font(.callout).foregroundStyle(Theme.muted)
      }
    }.padding(.horizontal,24).padding(.top,10)
      .frame(maxWidth:Theme.contentMaxWidth).frame(maxWidth:.infinity)
      .fixedSize(horizontal:false,vertical:true)
      .sheet(item:$presented){item in
        switch item.input{
        case let .approval(context,request):NativeApprovalSheet(store:native.approvals,context:context,request:request)
        case let .form(context,id):NativeFormSheet(store:native.forms,context:context,formID:id).nativeSharingReview(native,operation:.formAnswer)
        }
      }
  }
  @ViewBuilder private var inputButtons:some View{
      if let request=native.approvals.requests.first,let context=native.approvals.context{
        Button{presented=NativeInputPresentation(input:.approval(context,request))}label:{
          inputRow(dynamicTypeSize.isAccessibilitySize ? "Approval":"Approval needed",request.action,icon:"hand.raised")
        }.accessibilityLabel("Approval needed").accessibilityValue(request.action).accessibilityIdentifier("native-approval-open")
      }
      if let form=native.forms.pending.first,let context=native.forms.context{
        Button{presented=NativeInputPresentation(input:.form(context,form.id))}label:{
          inputRow(dynamicTypeSize.isAccessibilitySize ? "Question":"OpenCode has a question",form.title,icon:"questionmark.bubble")
        }.accessibilityLabel("OpenCode has a question").accessibilityValue(form.title).accessibilityIdentifier("native-form-open")
      }
  }
  @ViewBuilder private func inputRow(_ title:String,_ detail:String,icon:String)->some View{
    if compact{Image(systemName:icon).font(.system(size:22)).foregroundStyle(Theme.ink).frame(width:44,height:44)}else{
    HStack(spacing:12){Image(systemName:icon).font(.system(size:22));VStack(alignment:.leading,spacing:4){Text(title).font(.callout.weight(.semibold)).fixedSize(horizontal:false,vertical:true);if !dynamicTypeSize.isAccessibilitySize{Text(detail).font(.caption).lineLimit(2).fixedSize(horizontal:false,vertical:true)}};Spacer();Image(systemName:"chevron.right").font(.system(size:16,weight:.semibold))}
      .foregroundStyle(Theme.ink).padding(16).frame(maxWidth:.infinity,minHeight:52,alignment:.leading)
      .background(Theme.surface,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
    }
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
