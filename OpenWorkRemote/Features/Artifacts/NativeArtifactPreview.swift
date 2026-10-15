import SwiftUI
import OpenWorkRemoteCore

private struct NativeShareFile:Identifiable{let id=UUID();let url:URL}
struct NativeArtifactPreview:View {
  let file:OpenCodeResultFile
  let store:NativeResultStore
  let context:NativeResultContext
  @State private var share:NativeShareFile?
  @State private var sharing=false
  #if DEBUG && targetEnvironment(simulator)
  @State private var testSaved:String?
  #endif
  private var matches:Bool{store.context==context && file.target==context.target}
  var body:some View{
    ScrollView{
      VStack(alignment:.leading,spacing:24){
        Text("FROM YOUR PROJECT").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        Text(file.name).font(.title.weight(.semibold)).textSelection(.enabled)
        Text("Preview a temporary copy downloaded from your computer.").foregroundStyle(Theme.muted)
        if !matches{Text("The chat or connection changed. Open this file again from the current chat.").foregroundStyle(Theme.muted)}
        else if store.downloading{
          ProgressView("Downloading and checking file…")
          Button("Cancel download"){store.closePreview()}.frame(minHeight:44)
        }else if let ready=store.ready,ready.info.file.id==file.id,let preview=store.preview{
          Text(ByteCountFormatter.string(fromByteCount:Int64(ready.info.bytes),countStyle:.file)).font(.caption).foregroundStyle(Theme.muted)
          if let text=preview.text{
            Text(text).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(20).background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
              .accessibilityIdentifier("native-result-preview-text")
          }else if let url=preview.imageURL,let image=UIImage(contentsOfFile:url.path){
            Image(uiImage:image).resizable().scaledToFit().accessibilityLabel(ready.info.previewKind == .pdf ? "PDF page \(preview.page) of \(preview.pageCount)":"Preview of \(file.name)")
          }else{Label("This document can be shared or saved without a preview.",systemImage:"doc").foregroundStyle(Theme.muted)}
          if preview.truncated{Text("This preview shows part of the text. Sharing exports the complete downloaded file.").font(.callout).foregroundStyle(Theme.muted)}
          if preview.pageCount>1{
            HStack{Button("Previous page"){Task{await store.showPage(preview.page-1,context:context)}}.disabled(preview.page<=1 || store.loadingPage);Spacer();Text("\(preview.page) / \(preview.pageCount)").font(.caption);Spacer();Button("Next page"){Task{await store.showPage(preview.page+1,context:context)}}.disabled(preview.page>=preview.pageCount || store.loadingPage)}.frame(minHeight:44)
          }
        }
        if matches,let notice=store.notice{Text(notice).font(.callout).foregroundStyle(Theme.muted)}
        Button("Download current file"){Task{await store.open(file,context:context)}}.frame(minHeight:44).disabled(!matches || store.downloading)
        Text("Only this file will be shared. Choose its destination in the share sheet.").font(.callout).foregroundStyle(Theme.muted)
        Button{
          sharing=true
          Task{let url=await store.prepareShare(context:context);if matches,let url{share=NativeShareFile(url:url)};sharing=false}
        }label:{HStack{Text("Share or save a copy");if sharing{ProgressView()}}}.buttonStyle(PrimaryButtonStyle())
          .disabled(!matches || !store.canShare || store.ready?.info.file.id != file.id || sharing)
          .accessibilityIdentifier("native-result-share")
        #if DEBUG && targetEnvironment(simulator)
        if let testSaved{Text("Test copy saved: "+testSaved).accessibilityIdentifier("native-result-test-saved")}
        #endif
      }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
    }.background(Theme.background).navigationTitle("Preview file").navigationBarTitleDisplayMode(.inline)
      .task(id:file.id+context.id.uuidString){await store.open(file,context:context)}
      .onDisappear{if share==nil{store.closePreview()}}
      .onChange(of:store.context){_,value in if value != context{share=nil}}
      .sheet(item:$share){item in
        #if DEBUG && targetEnvironment(simulator)
        ArtifactShareSheet(url:item.url,completion:{share=nil},testSaved:{testSaved=$0})
        #else
        ArtifactShareSheet(url:item.url,completion:{share=nil})
        #endif
      }
  }
}
