import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import OpenWorkRemoteCore

private struct NativeSelectedPhoto:Transferable,Sendable {
  let png:Data
  static var transferRepresentation:some TransferRepresentation{
    FileRepresentation(importedContentType:.image){received in
      NativeSelectedPhoto(png:try await ProtectedAttachmentFiles.shared.normalizedPhoto(received.file,maximumPixelSize:2000))
    }
  }
}
struct NativeAttachmentPicker:View {
  let store:NativeAttachmentStore
  let context:NativeAttachmentContext
  @Environment(\.dismiss) private var dismiss
  @State private var photo:PhotosPickerItem?
  @State private var importing=false
  @State private var browse=false
  @State private var error:String?
  private var available:Bool{store.context==context && store.canChoose && !importing}
  var body:some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:20){
          Text("ATTACHMENTS").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
          Text("Give your chat\na little context.").font(.largeTitle.weight(.semibold))
          Text("Choose a photo or PDF. You can remove it before sending.").foregroundStyle(Theme.muted)
          if store.context != context{Text("This chat changed. Close this sheet and open attachments in the current chat.").foregroundStyle(Theme.muted)}
          VStack(spacing:12){
            PhotosPicker(selection:$photo,matching:.images,preferredItemEncoding:.current){AttachmentChoice("Choose photos",symbol:"photo")}.disabled(!available)
            Button{browse=true}label:{AttachmentChoice("Browse files",symbol:"doc")}.disabled(!available)
          }.padding(.vertical,12)
          if importing{ProgressView("Preparing selected file…")}
          if let error{Text(error).foregroundStyle(.red)}
          if let notice=store.notice{Text(notice).font(.callout).foregroundStyle(Theme.muted)}
          if store.context==context{
            ForEach(store.rows){row in
              VStack(alignment:.leading,spacing:8){
                Text(row.file.name).font(.callout.weight(.semibold))
                Text(label(row)).font(.caption).foregroundStyle(Theme.muted)
                if row.phase == .preparing{ProgressView("Preparing on your computer…")}
                HStack{
                  if [.failed,.selected,.uploadUnknown].contains(row.phase){
                    Button(row.phase == .uploadUnknown ? "Prepare a new copy":"Retry"){Task{await store.prepare(row.id,context:context)}}.frame(minHeight:44)
                      .disabled(store.journal.pending(for:context.target) != nil)
                  }
                  Button(row.phase == .preparing ? "Cancel preparation":"Remove",role:.destructive){
                    if row.phase == .preparing{store.cancelPreparation(row.id,context:context)}
                    else{Task{await store.remove(row.id,context:context)}}
                  }.frame(minHeight:44).disabled(store.journal.pending(for:context.target) != nil)
                }
              }.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                .accessibilityIdentifier("native-attachment-row-"+row.id.uuidString.lowercased())
            }
          }
          #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("-ui-testing-native-app"){
            Button("Use fixture photo"){
              importing=true
              Task{
                defer{importing=false}
                do{try await add(store.files.savePhotoPNG(Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=")!))}
                catch{self.error="The sample could not be prepared."}
              }
            }.disabled(!available).accessibilityIdentifier("native-fixture-photo")
          }
          #endif
          Text("Photos become PNGs up to 2,000 pixels on the longest edge. Location and camera metadata are not copied. Your original stays unchanged.").font(.footnote).foregroundStyle(Theme.muted)
          Text("OpenCode receives supported media when you send your message. Other files are uploaded now to a temporary location for the model’s tools. Removing a selection does not delete a temporary copy already on the computer.").font(.footnote).foregroundStyle(Theme.muted)
          Text("Up to four files, 20 MiB per file and 40 MiB per message. The computer or model may allow less.").font(.footnote).foregroundStyle(Theme.muted)
          Button("Add to message"){dismiss()}.buttonStyle(PrimaryButtonStyle())
        }.padding(24).frame(maxWidth:620,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).foregroundStyle(Theme.ink).navigationTitle("Add to your message").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}.accessibilityIdentifier("native-attachment-done")}}
        .onChange(of:photo){_,value in
          guard let value else{return};importing=true;error=nil
          Task{
            defer{importing=false;photo=nil}
            do{
              guard let selected=try await value.loadTransferable(type:NativeSelectedPhoto.self) else{throw RemoteError.invalidResponse}
              try await add(store.files.savePhotoPNG(selected.png))
            }catch{self.error="This photo could not be prepared. Choose a JPEG, HEIC or PNG up to 20 MiB."}
          }
        }
        .fileImporter(isPresented:$browse,allowedContentTypes:[.pdf,.jpeg,.heic,.png],allowsMultipleSelection:false){result in
          guard case let .success(urls)=result,let selected=urls.first else{return}
          importing=true;error=nil
          Task{
            defer{importing=false}
            do{
              if selected.pathExtension.lowercased()=="pdf"{try await add(store.files.importPDF(selected))}
              else{try await add(store.files.savePhotoPNG(store.files.normalizedPhoto(selected,maximumPixelSize:2000)))}
            }catch{self.error="This file could not be prepared. Choose a supported photo or PDF up to 20 MiB, and check free storage."}
          }
        }
    }
  }
  private func add(_ file:LocalAttachmentFile) async throws{
    do{try await store.add(file,context:context)}
    catch{
      if !store.journal.attachments(for:context.target).contains(where:{$0.id==file.id}){try? await store.files.remove(file)}
      throw error
    }
  }
  private func label(_ row:NativeSelectedAttachment)->String{
    switch row.phase{
    case .selected:return "Selected"
    case .preparing:return "Preparing"
    case .ready:return row.prepared?.placement == .inline ? "Ready · inline media":"Ready · computer file for tools"
    case .failed:return "Preparation failed; your selected file is kept"
    case .uploadUnknown:return "Upload unconfirmed; a temporary copy may exist on the computer"
    }
  }
}
