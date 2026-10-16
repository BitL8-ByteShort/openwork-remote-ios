import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import OpenWorkRemoteCore

struct ComposerView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(AppModel.self) private var model
  @FocusState private var focused: Bool
  #if DEBUG
  @State private var attachments: AttachmentPresentation?
  @State private var skills=false
  #endif
  @State private var nativeSkills:NativeWorkspaceContext?
  @State private var nativeAttachments:NativeAttachmentContext?
  @State private var selectedPhoto:PhotosPickerItem?
  @State private var choosingPhoto=false
  @State private var choosingFile=false
  @State private var selectionContext:NativeAttachmentContext?
  @State private var importing=false
  @State private var attachmentError:String?
  var body: some View {
    VStack(spacing: 8) {
      if let store=model.native?.attachments,let context=store.context,!store.rows.isEmpty{
        ScrollView(.horizontal){HStack{
          ForEach(store.rows){row in
            Button{nativeAttachments=context}label:{Label(row.file.name,systemImage:row.phase == .ready ? "paperclip":"arrow.up.doc")
              .font(.caption).padding(10).background(Theme.surface,in:Capsule())}
              .accessibilityValue(row.phase == .ready ? "Ready":row.phase == .preparing ? "Preparing":"Selected")
              .accessibilityIdentifier("native-attachment-chip-"+row.id.uuidString.lowercased())
          }
        }}
      }
      if importing{ProgressView("Adding attachment…").font(.caption)}
      if let attachmentError{Text(attachmentError).font(.caption).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
      if !model.selectedSkillIDs.isEmpty {
        ScrollView(.horizontal){HStack{ForEach(model.selectedSkillIDs,id:\.self){id in Button{model.removeSelectedSkill(id)}label:{Label(skillName(id)+" · Remove",systemImage:"sparkles").font(.caption).padding(10).background(Theme.surface,in:Capsule())}.disabled(model.sending || model.uncertain).accessibilityIdentifier("selected-skill-"+id)}}}
      }
      #if DEBUG
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
      #endif
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
          if let store=model.native?.attachments,let context=store.context{
            Button("Photos",systemImage:"photo"){focused=false;selectionContext=context;choosingPhoto=true}
              .disabled(!store.canChoose || importing)
            Button("Files",systemImage:"doc"){focused=false;selectionContext=context;choosingFile=true}
              .disabled(!store.canChoose || importing)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-native-app"){
              Button("Use fixture photo"){
                focused=false;selectionContext=context
                importAttachment{
                  try await store.files.savePhotoPNG(Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=")!)
                }
              }.disabled(!store.canChoose || importing).accessibilityIdentifier("native-fixture-photo")
            }
            #endif
          }
          #if DEBUG
          if model.native == nil{
            Button("Photos or files",systemImage:"paperclip"){
              focused=false
              if let context=model.attachmentContext{attachments=AttachmentPresentation(context:context)}
            }
          }
          #endif
          Button("Skills",systemImage:"sparkles"){
            focused=false
            if let context=model.native?.workspace.context{nativeSkills=context}
            #if DEBUG
            if model.native == nil { skills=true }
            #endif
          }
        }label:{Image(systemName:"plus").font(.system(size:20)).frame(width:44,height:44)}
          .disabled(model.selectedSession == nil || model.sending).accessibilityLabel("Add to message").accessibilityIdentifier("composer-add")
        TextField(
          dynamicTypeSize.isAccessibilitySize ? "Message":"Message \(model.serviceName)", text: Binding(get: { model.draft }, set: { model.draft = $0 }),
          axis: .vertical
        ).font(.body).lineLimit(1...(dynamicTypeSize.isAccessibilitySize ? 3:6)).focused($focused).padding(.vertical, 14)
          .disabled(model.selectedSession==nil)
          .accessibilityHint(model.selectedSession==nil ? "Choose a chat or start a new one before typing.":"")
          .accessibilityLabel("Message \(model.serviceName)").accessibilityIdentifier("composer")
        if model.isRunning || model.stopRequested {
          Button {
            Task { await model.stop() }
          } label: {
            if model.stopRequested {
              ProgressView().tint(Theme.onAccent)
            } else {
              Image(systemName: "stop.fill").font(.system(size:18,weight:.semibold))
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
            if model.native?.preparingSend==true{ProgressView().frame(width:44,height:44)}else{Image(systemName: "arrow.up").font(.system(size:20,weight:.semibold)).frame(
              width: 44, height: 44)}
          }.background(model.canSend ? Theme.accent : Theme.line, in: Circle()).foregroundStyle(
            model.canSend ? Theme.onAccent : Theme.muted
          ).disabled(!model.canSend || importing).accessibilityLabel("Send message").accessibilityIdentifier(
            "send-message")
        }
      }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8).background(
        Theme.surface, in: RoundedRectangle(cornerRadius: 26))
      if !dynamicTypeSize.isAccessibilitySize || model.connection != .ready{
      Text(model.connection == .ready ? "Runs on your computer" : model.connectionLabel).font(
        .caption
      ).foregroundStyle(Theme.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).frame(maxWidth: .infinity)
      }
    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
      .frame(maxWidth: Theme.contentMaxWidth).frame(maxWidth: .infinity).background(Theme.background)
      #if DEBUG
      .sheet(isPresented:$skills){NavigationStack{SkillListView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){skills=false}}}}}
      #endif
      .sheet(item:$nativeSkills){context in
        if let store=model.native?.workspace{NavigationStack{NativeSkillListView(store:store,context:context,onSelection:{if nativeSkills==context{nativeSkills=nil}}).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){nativeSkills=nil}.accessibilityIdentifier("native-skills-done")}}}}
      }
      #if DEBUG
      .sheet(item:$attachments) { AttachmentPicker(context:$0.context) }
      #endif
      .sheet(item:$nativeAttachments){context in
        if let store=model.native?.attachments{NativeAttachmentPicker(store:store,context:context)}
      }
      .photosPicker(isPresented:$choosingPhoto,selection:$selectedPhoto,matching:.images,preferredItemEncoding:.current)
      .onChange(of:selectedPhoto){_,photo in
        guard let photo,let files=model.native?.attachments.files else{return}
        importAttachment{
          guard let selected=try await photo.loadTransferable(type:NativeSelectedPhoto.self) else{throw RemoteError.invalidResponse}
          return try await files.savePhotoPNG(selected.png)
        }
      }
      .fileImporter(isPresented:$choosingFile,allowedContentTypes:[.pdf,.jpeg,.heic,.png],allowsMultipleSelection:false){result in
        guard case let .success(urls)=result,let selected=urls.first,let files=model.native?.attachments.files else{return}
        importAttachment{
          if selected.pathExtension.lowercased()=="pdf"{return try await files.importPDF(selected)}
          return try await files.savePhotoPNG(files.normalizedPhoto(selected,maximumPixelSize:2000))
        }
      }
      .nativeSharingReview(nativeAttachments == nil ? model.native:nil,operation:.attachment)
      #if DEBUG
      .task(id:model.attachmentRefreshID) { await model.refreshAttachments() }
      #endif
  }
  private func importAttachment(_ makeFile:@escaping @Sendable ()async throws->LocalAttachmentFile){
    guard !importing,let context=selectionContext,let store=model.native?.attachments,store.context==context else{return}
    importing=true;attachmentError=nil
    Task{
      defer{importing=false;selectedPhoto=nil}
      do{
        let file=try await makeFile()
        do{try await store.add(file,context:context)}
        catch{
          if !store.journal.attachments(for:context.target).contains(where:{$0.id==file.id}){try? await store.files.remove(file)}
          throw error
        }
      }catch{
        if store.context==context{attachmentError="This file could not be added. Choose a supported photo or PDF up to 20 MiB. Your model needs image support to read photos."}
      }
    }
  }
  private func skillName(_ id: String) -> String {
    if let name=model.native?.workspace.selectedSkills.first(where:{$0.id==id})?.name { return name }
    #if DEBUG
    if let name=model.skills.catalog?.items.first(where:{$0.id==id})?.name { return name }
    #endif
    return "Selected skill"
  }

}
#if DEBUG
private struct AttachmentPresentation: Identifiable {
  let id = UUID()
  let context: AttachmentContext
}

#endif
