import SwiftUI
import OpenWorkRemoteCore

struct NativeArtifactListView:View {
  let store:NativeResultStore
  let context:NativeResultContext
  @Environment(\.dismiss) private var dismiss
  var body:some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:24){
          Text("RESULTS").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
          Text("Ready to take\nwith you.").font(.largeTitle.weight(.semibold))
          Text("Files referenced or changed in loaded replies. Tap a file to download a temporary preview, or browse this chat’s project.").foregroundStyle(Theme.muted)
          if store.context != context{Text("This chat changed. Open files again from the current chat.").foregroundStyle(Theme.muted)}
          else{
            if store.items.isEmpty{Text("No supported file references or changes in the loaded replies yet.").foregroundStyle(Theme.muted)}
            ForEach(store.items){file in
              NavigationLink{NativeArtifactPreview(file:file,store:store,context:context)}label:{
                HStack{VStack(alignment:.leading,spacing:8){Text(file.name).font(.headline);Text("On your computer").font(.caption).foregroundStyle(Theme.muted)};Spacer();Image(systemName:"chevron.right")}
                  .padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Theme.raised,in:RoundedRectangle(cornerRadius:18))
                  .overlay(RoundedRectangle(cornerRadius:18).stroke(Theme.line))
              }.foregroundStyle(Theme.ink).accessibilityIdentifier("native-result-row-"+file.id)
            }
            NavigationLink{NativeProjectFileBrowser(store:store,context:context,directory:nil)}label:{Label("Browse project files",systemImage:"folder").frame(minHeight:44)}
              .accessibilityIdentifier("native-project-files")
            if store.unsupportedReferences>0{Label("Some file references need your computer. Outside-project paths and unsupported outputs are not downloaded.",systemImage:"desktopcomputer").font(.callout).foregroundStyle(Theme.muted)}
          }
          Text("Downloads begin when you choose a file. Sharing or saving a copy is a separate action. Current contents can differ from the original reply.").font(.callout).foregroundStyle(Theme.muted)
        }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).navigationTitle("Files from this chat").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){store.closePreview();dismiss()}.accessibilityIdentifier("native-results-done")}}
    }
  }
}
struct NativeProjectFileBrowser:View {
  let store:NativeResultStore
  let context:NativeResultContext
  let directory:String?
  @State private var entries:[OpenCodeProjectFile]=[]
  @State private var loading=false
  @State private var error:String?
  @State private var retry=UUID()
  var body:some View{
    List{
      Section{Text("Only files inside this chat’s current project can be downloaded. Choose a file to preview it.").font(.callout).foregroundStyle(Theme.muted)}
      if loading{ProgressView("Loading files…")}
      if let error{Section{Text(error).foregroundStyle(Theme.muted);Button("Try again"){retry=UUID()}}}
      ForEach(entries){entry in
        if entry.type=="directory"{
          let path=entry.path.hasSuffix("/") ? String(entry.path.dropLast()):entry.path
          NavigationLink{NativeProjectFileBrowser(store:store,context:context,directory:path)}label:{Label((path as NSString).lastPathComponent,systemImage:"folder")}
        }else if let file=try? OpenCodeResultFile(relativePath:entry.path,target:context.target){
          NavigationLink{NativeArtifactPreview(file:file,store:store,context:context)}label:{Label(file.name,systemImage:"doc")}
        }else{Text("This filename needs your computer.").foregroundStyle(Theme.muted)}
      }
      if !loading,error==nil,entries.isEmpty{Text("No files in this folder.").foregroundStyle(Theme.muted)}
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(directory.map{($0 as NSString).lastPathComponent} ?? "Project files")
      .task(id:retry){
        loading=true;error=nil
        do{let values=try await store.projectFiles(directory:directory,context:context);guard !Task.isCancelled else{return};entries=values}
        catch{if !Task.isCancelled{self.error="Files could not be loaded. Check the connection or continue on your computer."}}
        if !Task.isCancelled{loading=false}
      }
  }
}
