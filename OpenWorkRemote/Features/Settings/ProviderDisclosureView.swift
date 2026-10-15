import SwiftUI
import OpenWorkRemoteCore

private struct ProviderDisclosureView:View{
  let native:NativeAppCoordinator
  let review:ProviderDisclosureReview
  private var store:ProviderDisclosureStore{native.sharing}
  var body:some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:22){
          Label("Before you share",systemImage:"hand.raised").font(.headline).foregroundStyle(Theme.accent)
          Text("Review your AI destination.").font(.largeTitle.weight(.semibold))
          VStack(alignment:.leading,spacing:10){
            Text("Paired OpenCode server").font(.caption).foregroundStyle(Theme.muted)
            Text(verbatim:review.destination.origin).font(.callout.monospaced()).textSelection(.enabled)
            Text(verbatim:review.destination.model.providerID).font(.headline)
            Text(verbatim:review.destination.model.id).font(.callout).foregroundStyle(Theme.muted)
            if let endpoint=review.destination.reportedEndpoint{
              Text("Reported base address").font(.caption).foregroundStyle(Theme.muted)
              Text(verbatim:endpoint).font(.callout.monospaced()).textSelection(.enabled)
            }
          }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:20))
          Text("Final destination is unknown").font(.headline).accessibilityIdentifier("sharing-unknown-destination")
          Text("OpenCode’s model packages, account settings and plugins may change or add destinations. PocketWork cannot verify their final addresses. Review those settings on your computer before allowing sharing.")
            .font(.callout).foregroundStyle(Theme.muted)
          VStack(alignment:.leading,spacing:10){
            Text("What may be shared").font(.headline)
            ForEach(OpenCodeSharedData.allCases.filter{review.classes.contains($0)},id:\.self){item in
              Label(label(item),systemImage:"checkmark").font(.callout)
            }
          }
          Text("Your computer runs the agent. Its configured providers, tools and services may receive this data under their own policies. Larger attachments can be uploaded to your computer during preparation, before the message is sent.")
            .font(.callout).foregroundStyle(Theme.muted)
          Text("This permission is saved on this device for the reported connection, provider configuration and data types. Changed information requires another review. You can remove saved sharing permissions in Data Controls.")
            .font(.footnote).foregroundStyle(Theme.muted)
          if let notice=store.notice{Text(notice).font(.callout).foregroundStyle(Theme.muted).accessibilityIdentifier("sharing-review-notice")}
          if store.saving{ProgressView("Checking and saving permission…")}
          Button("Allow with destination unknown"){
            guard let client=native.connection.client else{return}
            Task{_ = await store.approve(review,using:client,acknowledgesUnknownDestination:true)}
          }.buttonStyle(PrimaryButtonStyle()).disabled(store.saving || store.review?.id != review.id || native.connection.state != .ready)
            .accessibilityIdentifier("sharing-review-allow")
          Text("After allowing, retry Send, the question reply or file preparation. Allowing here does not perform it.")
            .font(.footnote).foregroundStyle(Theme.muted)
        }.padding(24).frame(maxWidth:620,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).foregroundStyle(Theme.ink).navigationTitle("Sharing review").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){store.cancelReview()}.frame(minHeight:44).accessibilityIdentifier("sharing-review-cancel")}}
    }
  }
  private func label(_ value:OpenCodeSharedData)->String{
    switch value{
    case .conversation:"Messages, question answers and chat history"
    case .projectContext:"Project content the agent reads"
    case .toolResults:"Tool results and related service requests"
    case .photos:"Selected photos and filenames"
    case .documents:"Selected documents and filenames"
    case .skillInstructions:"Selected skill instructions and references"
    }
  }
}
private struct NativeSharingReviewPresenter:ViewModifier{
  let native:NativeAppCoordinator
  let operation:OpenCodeSharingOperation
  func body(content:Content)->some View{
    content.sheet(item:Binding(get:{native.sharing.review?.operation==operation ? native.sharing.review:nil},set:{if $0==nil,native.sharing.review?.operation==operation{native.sharing.cancelReview()}})){review in
      ProviderDisclosureView(native:native,review:review).id(review.id)
    }
  }
}
extension View{
  @ViewBuilder func nativeSharingReview(_ native:NativeAppCoordinator?,operation:OpenCodeSharingOperation)->some View{
    if let native{modifier(NativeSharingReviewPresenter(native:native,operation:operation))}else{self}
  }
}
