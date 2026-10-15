import SwiftUI

struct ComposerView: View {
  @Environment(AppModel.self) private var model
  @FocusState private var focused: Bool
  @State private var attachments: AttachmentPresentation?
  @State private var skills=false
  @State private var nativeSkills:NativeWorkspaceContext?
  @State private var nativeAttachments:NativeAttachmentContext?
  var body: some View {
    VStack(spacing: 8) {
      if let store=model.native?.attachments,let context=store.context,!store.rows.isEmpty{
        ScrollView(.horizontal){HStack{
          ForEach(store.rows){row in
            Button{nativeAttachments=context}label:{Label(row.file.name,systemImage:row.phase == .ready ? "paperclip":"arrow.up.doc")
              .font(.caption).padding(10).background(Theme.surface,in:Capsule())}
              .accessibilityIdentifier("native-attachment-chip-"+row.id.uuidString.lowercased())
          }
        }}
      }
      if !model.selectedSkillIDs.isEmpty {
        ScrollView(.horizontal){HStack{ForEach(model.selectedSkillIDs,id:\.self){id in Button{model.removeSelectedSkill(id)}label:{Label((model.native?.workspace.selectedSkills.first{$0.id==id}?.name ?? model.skills.catalog?.items.first{$0.id==id}?.name ?? "Selected skill")+" · Remove",systemImage:"sparkles").font(.caption).padding(10).background(Theme.surface,in:Capsule())}.disabled(model.sending || model.uncertain).accessibilityIdentifier("selected-skill-"+id)}}}
      }
      if !model.attachments.rows.isEmpty, let context = model.attachmentContext {
        ScrollView(.horizontal) {
          HStack {
            ForEach(model.attachments.rows) { row in
              Button { attachments = AttachmentPresentation(context:context) } label: {
                Label(row.file.name,systemImage:row.phase == .ready ? "paperclip" : "arrow.up.doc")
                  .font(.caption).padding(10).background(Theme.surface,in:Capsule())
              }.accessibilityLabel(row.file.name + (row.phase == .ready ? ", ready to send" : ", upload pending"))
            }
          }
        }
      }
      if model.uncertain {
        VStack(alignment: .leading, spacing: 8) {
          Label("Delivery is uncertain", systemImage: "exclamationmark.circle").font(
            .callout.weight(.semibold))
          Text("Check the conversation before trying again. Your draft is saved.").font(.caption)
          Button("Check conversation") { Task { await model.checkConversation() } }.font(
            .callout.weight(.semibold)
          ).frame(minHeight: 44)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(
          .orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
      }
      HStack(alignment: .bottom, spacing: 8) {
        Menu {
          Button("Photos or files",systemImage:"paperclip"){
            focused=false
            if let context=model.native?.attachments.context{nativeAttachments=context}
            else if let context=model.attachmentContext{attachments=AttachmentPresentation(context:context)}
          }
          Button("Skills",systemImage:"sparkles"){
            focused=false
            if let context=model.native?.workspace.context{nativeSkills=context}else{skills=true}
          }
        }label:{Image(systemName:"plus").font(.title3).frame(width:44,height:44)}
          .disabled(model.selectedSession == nil || model.sending).accessibilityLabel("Add to message").accessibilityIdentifier("composer-add")
        TextField(
          "Message \(model.serviceName)", text: Binding(get: { model.draft }, set: { model.draft = $0 }),
          axis: .vertical
        ).font(.body).lineLimit(1...6).focused($focused).padding(.vertical, 14)
          .accessibilityIdentifier("composer")
        if model.isRunning || model.stopRequested {
          Button {
            Task { await model.stop() }
          } label: {
            if model.stopRequested {
              ProgressView().tint(Theme.onAccent)
            } else {
              Image(systemName: "stop.fill").font(.body.weight(.semibold))
            }
          }.frame(width: 44, height: 44).background(Theme.accent, in: Circle()).foregroundStyle(
            Theme.onAccent
          ).disabled(model.stopRequested || model.connection != .ready).accessibilityLabel(
            model.stopRequested ? "Stopping" : "Stop response")
        } else {
          Button {
            focused = false
            Task { await model.send() }
          } label: {
            if model.native?.preparingSend==true{ProgressView().frame(width:44,height:44)}else{Image(systemName: "arrow.up").font(.title3.weight(.semibold)).frame(
              width: 44, height: 44)}
          }.background(model.canSend ? Theme.accent : Theme.line, in: Circle()).foregroundStyle(
            model.canSend ? Theme.onAccent : Theme.muted
          ).disabled(!model.canSend).accessibilityLabel("Send message").accessibilityIdentifier(
            "send-message")
        }
      }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8).background(
        Theme.surface, in: RoundedRectangle(cornerRadius: 26))
      Text(model.connection == .ready ? "Runs on your computer" : model.connectionLabel).font(
        .caption
      ).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8).background(Theme.background)
      .sheet(isPresented:$skills){NavigationStack{SkillListView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){skills=false}}}}}
      .sheet(item:$nativeSkills){context in
        if let store=model.native?.workspace{NavigationStack{NativeSkillListView(store:store,context:context,onSelection:{if nativeSkills==context{nativeSkills=nil}}).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){nativeSkills=nil}.accessibilityIdentifier("native-skills-done")}}}}
      }
      .sheet(item:$attachments) { AttachmentPicker(context:$0.context) }
      .sheet(item:$nativeAttachments){context in
        if let store=model.native?.attachments{NativeAttachmentPicker(store:store,context:context)}
      }
      .task(id:model.attachmentRefreshID) { await model.refreshAttachments() }
  }
}
private struct AttachmentPresentation: Identifiable {
  let id = UUID()
  let context: AttachmentContext
}
