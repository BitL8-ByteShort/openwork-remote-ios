import SwiftUI
import OpenWorkRemoteCore

struct NativeModelSettingsView:View {
  let store:NativeControlStore
  let context:NativeControlContext
  var onFiles:(()->Void)? = nil
  var onChanges:(()->Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var review:NativeControlReview?
  @State private var draft:NativeModelDraft?
  @State private var agentID:String?
  private var snapshot:NativeControlSnapshot?{store.context==context ? store.snapshot : nil}
  private var selected:OpenCodeModel?{snapshot?.models.first{$0.selectionKey==draft?.selectedKey}}
  var body:some View {
    NavigationStack {
      Form {
        if let onFiles{Section("This chat"){Button(action:onFiles){Label("Files from this chat",systemImage:"doc.on.doc")}.accessibilityIdentifier("native-chat-files-settings")}}
        if let onChanges{Section{Button(action:onChanges){Label("Working-copy changes",systemImage:"doc.text.magnifyingglass")}.accessibilityIdentifier("native-chat-changes-settings")}}
        if store.loading{ProgressView("Loading settings…")}
        NativeControlIssueView(store:store){Task{await reload()}}
        if let snapshot,let review,let draft {
          Section {
            NavigationLink {
              NativeModelPicker(models:snapshot.models,selectedKey:draft.selectedKey){model in self.draft?.choose(model)}
            } label: {
              VStack(alignment:.leading,spacing:6){
                Text("Model").font(.caption).foregroundStyle(Theme.muted)
                Text(selected?.name ?? draft.current?.id ?? "OpenCode default").font(.headline)
                if let provider=selected?.providerID ?? draft.current?.providerID{Text(provider).font(.caption).foregroundStyle(Theme.muted)}
              }.padding(.vertical,6)
            }.accessibilityIdentifier("native-model-picker")
            if let selected,!selected.variants.isEmpty {
              Picker("Variant",selection:Binding(get:{self.draft?.variant ?? ""},set:{self.draft?.variant=$0})) {
                Text("Model default").tag("")
                ForEach(selected.variants,id:\.id){Text($0.id).tag($0.id)}
              }.accessibilityIdentifier("native-model-variant")
            } else {LabeledContent("Variant",value:draft.variant.isEmpty ? "Model default" : draft.variant)}
            if draft.selectedKey==nil,draft.current != nil {
              Text("The current model is not in the computer’s catalog. Choose an available model or reload; your selection has not changed.")
                .font(.callout).foregroundStyle(Theme.muted)
            }
            Button {
              guard let choice=draft.selection(in:snapshot.models) else{return}
              Task{_ = await store.setModel(choice,review:review);captureActual()}
            } label:{HStack{Text("Apply model to this chat");Spacer();if store.busy{ProgressView()}}}
              .disabled(!store.canEdit(context) || draft.selection(in:snapshot.models)==nil || OpenCodeModelRef.sameSelection(draft.selection(in:snapshot.models),draft.current))
              .accessibilityIdentifier("native-model-apply")
          } footer:{Text("Models and variants come from OpenCode on your computer. This changes only this chat.")}
          Section {
            Picker("Agent",selection:$agentID) {
              if review.session.agent==nil{Text("OpenCode default").tag(nil as String?)}
              ForEach(snapshot.agents.filter(\.selectable)){Text($0.name).tag(Optional($0.id))}
              if let current=review.session.agent,!snapshot.agents.contains(where:{$0.id==current}){
                Text(current+" (unavailable)").tag(Optional(current))
              }
            }.accessibilityIdentifier("native-agent-picker")
            if let agent=snapshot.agents.first(where:{$0.id==agentID}),let description=agent.description{Text(description).font(.callout).foregroundStyle(Theme.muted)}
            Button("Apply agent to this chat"){
              guard let agentID else{return}
              Task{_ = await store.setAgent(agentID,review:review);captureActual()}
            }.disabled(!store.canEdit(context) || agentID==nil || agentID==review.session.agent)
              .accessibilityIdentifier("native-agent-apply")
          } footer:{Text("Only agents available for direct conversations are listed. The computer confirms every change.")}
          Section{NavigationLink("Permissions"){NativePermissionsView(store:store,context:context)}}
        } else if !store.loading,store.issue==nil {Text("Open a connected chat to change its settings.")}
      }.scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Model & settings").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}.accessibilityIdentifier("native-settings-done")}}
    }.task(id:context){await reload()}
  }
  private func reload() async {if await store.load(context){captureActual()}}
  private func captureActual(){
    guard let snapshot else{return}
    draft=NativeModelDraft(snapshot:snapshot);agentID=snapshot.session.agent
    if let captured=store.review(context){review=captured}
  }
}
struct NativeModelPicker:View {
  let models:[OpenCodeModel]
  let selectedKey:Data?
  let choose:(OpenCodeModel)->Void
  @Environment(\.dismiss) private var dismiss
  @State private var search=""
  var body:some View {
    List {
      ForEach(models.filter{search.isEmpty || ($0.name+" "+$0.providerID).localizedCaseInsensitiveContains(search)},id:\.selectionKey){model in
        Button{choose(model);dismiss()}label:{
          HStack{
            VStack(alignment:.leading,spacing:5){Text(model.name);Text(model.providerID).font(.caption).foregroundStyle(Theme.muted)}
            Spacer()
            if selectedKey==model.selectionKey{Image(systemName:"checkmark").foregroundStyle(Theme.accent)}
            if !model.selectable{Text("Unavailable").font(.caption).foregroundStyle(Theme.muted)}
          }.padding(.vertical,4)
        }.disabled(!model.selectable).accessibilityIdentifier("native-model-choice-"+model.selectionKey.base64EncodedString())
      }
    }.searchable(text:$search,prompt:"Find a model").navigationTitle("Model")
      .scrollContentBackground(.hidden).background(Theme.background)
  }
}
struct NativeControlIssueView:View {
  let store:NativeControlStore
  var displaysActualValues=true
  let reload:()->Void
  var body:some View {
    if let issue=store.issue {
      Section {
        Text(message(issue)).foregroundStyle(issue == .allowReviewRequired ? Theme.muted : .red)
        if issue != .allowReviewRequired{Button("Reload settings",action:reload)}
      }
    }
  }
  private func message(_ issue:NativeControlIssue)->String {
    switch issue {
    case .unavailable:return "Settings could not be loaded. Check the connection and reload."
    case .authenticationRequired:return "OpenCode rejected this connection. Pair again with a fresh code from your computer."
    case .changeUnconfirmed:return displaysActualValues ? "The change could not be confirmed. The values shown were read from the computer. Review them before making another change." : "The change could not be confirmed. Reload the computer’s rules and review them before saving again."
    case .allowReviewRequired:return "Review the exact actions and resources before allowing them."
    case .locationChanged:return "This chat moved or is no longer available. Reopen it from Your Chats."
    }
  }
}
