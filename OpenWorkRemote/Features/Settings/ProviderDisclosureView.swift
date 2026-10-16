import SwiftUI
import OpenWorkRemoteCore

private struct ProviderDisclosureView:View{
  let native:NativeAppCoordinator
  let review:ProviderDisclosureReview
  @State private var details=false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  private var store:ProviderDisclosureStore{native.sharing}
  var body:some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:16){
          Text("Share with your AI?").font(.title3.weight(.semibold))
          VStack(alignment:.leading,spacing:5){
            Text(verbatim:review.destination.model.providerID).font(.headline)
            Text(verbatim:review.destination.model.id).font(.callout).foregroundStyle(Theme.muted)
            Text("Reported by your paired OpenCode computer").font(.caption).foregroundStyle(Theme.muted)
          }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
          VStack(alignment:.leading,spacing:6){
            Text("What will be shared").font(.subheadline.weight(.semibold))
            Text(OpenCodeSharedData.allCases.filter{review.classes.contains($0)}.map(label).joined(separator:", ")+".").font(.callout)
          }
          Text("Your computer’s AI services may receive this data. Additional destinations cannot be verified.")
            .font(.footnote).foregroundStyle(Theme.muted).accessibilityIdentifier("sharing-unknown-destination")
          DisclosureGroup(isExpanded:$details){
            VStack(alignment:.leading,spacing:12){
              Text("Paired OpenCode server").font(.subheadline.weight(.semibold))
              Text(verbatim:review.destination.origin).font(.footnote.monospaced()).textSelection(.enabled)
              if let endpoint=review.destination.reportedEndpoint{
                Text("Reported provider address").font(.subheadline.weight(.semibold))
                Text(verbatim:endpoint).font(.footnote.monospaced()).textSelection(.enabled)
              }
              Text("OpenCode’s model packages, account settings, tools and plugins may change or add destinations. Review those settings on your computer. Their own privacy policies apply.")
              Text("Larger attachments may be uploaded to your computer while they are prepared, before you send the message.")
              Text("Permission is saved on this device for this reported connection, provider configuration and data types. Changes require another review. You can clear it in Data Controls.")
            }.font(.footnote).foregroundStyle(Theme.muted).padding(.top,10)
              .fixedSize(horizontal:false,vertical:true)
          }label:{Text("Connection and privacy details").font(.callout)}
            .accessibilityIdentifier("sharing-review-details")
          if let notice=store.notice,notice != "Review where your data may be shared before continuing."{
            Text(notice).font(.callout).foregroundStyle(Theme.muted).accessibilityIdentifier("sharing-review-notice")
          }
          if store.saving{ProgressView("Checking and saving permission…")}
        }.padding(20).frame(maxWidth:620,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).foregroundStyle(Theme.ink).navigationTitle("Sharing").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge:.bottom){
          VStack(spacing:8){
            Button("Allow sharing"){
              guard let client=native.connection.client else{return}
              Task{
                if await store.approve(review,using:client,acknowledgesUnknownDestination:true),review.operation == .attachment{
                  await native.attachments.resumeSharingPreparation(target:review.target)
                }
              }
            }.buttonStyle(PrimaryButtonStyle()).disabled(store.saving || store.review?.id != review.id || native.connection.state != .ready)
              .accessibilityIdentifier("sharing-review-allow")
            Text(review.operation == .attachment ? "Continues preparing your selected file, which may upload to your computer. You choose when to send." : "Saved for this setup. You choose when to send.").font(.caption).foregroundStyle(Theme.muted)
              .fixedSize(horizontal:false,vertical:true)
          }.padding(.horizontal,20).padding(.vertical,12).frame(maxWidth:620).frame(maxWidth:.infinity).background(Theme.background)
        }
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){
          if review.operation == .attachment{native.attachments.cancelSharingPreparation(target:review.target)}
          store.cancelReview()
        }.frame(minHeight:44).accessibilityIdentifier("sharing-review-cancel")}}
    }.presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large]:[.height(500),.large])
      .presentationDragIndicator(.visible)
  }
  private func label(_ value:OpenCodeSharedData)->String{
    switch value{
    case .conversation:"Messages and chat history"
    case .projectContext:"project context"
    case .toolResults:"tool results"
    case .photos:"selected photos and filenames"
    case .documents:"selected documents and filenames"
    case .skillInstructions:"selected skill instructions"
    }
  }
}
private struct NativeSharingReviewPresenter:ViewModifier{
  let native:NativeAppCoordinator
  let operation:OpenCodeSharingOperation
  func body(content:Content)->some View{
    content.sheet(item:Binding(get:{native.sharing.review?.operation==operation ? native.sharing.review:nil},set:{
      if $0==nil,let review=native.sharing.review,review.operation==operation{
        if operation == .attachment{native.attachments.cancelSharingPreparation(target:review.target)}
        native.sharing.cancelReview()
      }
    })){review in
      ProviderDisclosureView(native:native,review:review).id(review.id)
    }
  }
}
extension View{
  @ViewBuilder func nativeSharingReview(_ native:NativeAppCoordinator?,operation:OpenCodeSharingOperation)->some View{
    if let native{modifier(NativeSharingReviewPresenter(native:native,operation:operation))}else{self}
  }
}
