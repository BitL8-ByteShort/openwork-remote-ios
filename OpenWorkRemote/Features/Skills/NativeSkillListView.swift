import SwiftUI
import OpenWorkRemoteCore

struct NativeSkillListView:View{
  let store:NativeWorkspaceStore
  let context:NativeWorkspaceContext
  var onSelection:(()->Void)?=nil
  @State private var search=""
  var body:some View{
    List{
      Section{Text("Previewing a skill does not run it. Select instructions for your next message; sending may invoke OpenCode plugins and tools under the computer’s approval rules.").font(.callout).foregroundStyle(Theme.muted)}
      if store.skillsLoading{ProgressView("Checking registered skills…")}
      if let notice=store.skillsNotice{Section{Text(notice).foregroundStyle(Theme.muted)}}
      if store.context==context{
        Section{
          ForEach(store.skills.filter{search.isEmpty || ($0.name+" "+$0.id+" "+($0.description ?? "")).localizedCaseInsensitiveContains(search)}){skill in
            NavigationLink{NativeSkillDetailView(store:store,context:context,skill:skill,onSelection:onSelection)}label:{
              VStack(alignment:.leading,spacing:6){
                HStack{Text(skill.name).font(.headline).lineLimit(2);if let selected=store.selectedSkills.first(where:{$0.id==skill.id}){Image(systemName:selected.fingerprint==skill.fingerprint ? "checkmark.circle.fill":"exclamationmark.circle").accessibilityLabel(selected.fingerprint==skill.fingerprint ? "Selected for next message":"Changed since selection")}}
                if let description=skill.description{Text(description).font(.caption).foregroundStyle(Theme.muted).lineLimit(3)}
              }.padding(.vertical,5)
            }.accessibilityIdentifier("native-skill-"+skill.id)
          }
          if store.skillsAvailable,store.skills.isEmpty{Text("No registered skills in this location.").foregroundStyle(Theme.muted)}
        }header:{Text("Registered on your computer")}
      }
      Section{Text("Add or edit host skills and scheduled work in OpenCode on your computer. This app does not create a second scheduler or edit host skill files.").font(.caption).foregroundStyle(Theme.muted)}
      Button("Refresh skills"){Task{await store.loadSkills(context)}}.disabled(store.skillsLoading || store.context != context)
    }.searchable(text:$search,prompt:"Find a skill by name").navigationTitle("Skills").scrollContentBackground(.hidden).background(Theme.background)
      .task(id:context){await store.loadSkills(context)}
  }
}
private struct NativeSkillDetailView:View{
  let store:NativeWorkspaceStore
  @State private var context:NativeWorkspaceContext
  @State private var skill:OpenCodeSkill
  var onSelection:(()->Void)?=nil
  @State private var error:String?
  @State private var pages:[String]=[]
  @State private var page=0
  init(store:NativeWorkspaceStore,context:NativeWorkspaceContext,skill:OpenCodeSkill,onSelection:(()->Void)?=nil){
    self.store=store;self.onSelection=onSelection;_context=State(initialValue:context);_skill=State(initialValue:skill)
  }
  private var current:Bool{store.context==context && store.skills.contains{$0.id==skill.id && $0.fingerprint==skill.fingerprint}}
  private var selected:Bool{store.selectedSkills.contains{$0.id==skill.id && $0.fingerprint==skill.fingerprint}}
  var body:some View{
    ScrollView{
      VStack(alignment:.leading,spacing:20){
        Text(skill.name).font(.title2.weight(.semibold))
        if let description=skill.description{Text(description).foregroundStyle(Theme.muted)}
        Text("Read-only preview. At admission, OpenCode resolves the instructions again and may add related file names or plugin content.").font(.caption).foregroundStyle(Theme.muted)
        if !current{Text("This skill changed or the chat moved. Go back and refresh to review its current instructions.").foregroundStyle(.red)}
        if pages.isEmpty{ProgressView("Preparing preview…")}else{Text(pages[min(page,pages.count-1)]).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
        Text(skill.path).font(.caption.monospaced()).foregroundStyle(Theme.muted).textSelection(.enabled)
        if let error{Text(error).foregroundStyle(.red)}
        Button(selected ? "Remove from next message":"Use this version for next message"){
          Task{do{try await store.choose(skill,selected:!selected,context:context);if store.context==context{onSelection?()}}catch{self.error="The skill selection could not be saved. Refresh the skill or unlock this device and try again."}}
        }.buttonStyle(PrimaryButtonStyle()).disabled(pages.isEmpty || !current || !store.canChooseSkills(context) || !store.skillsAvailable || store.skillsLoading).accessibilityIdentifier("native-skill-use")
      }.padding(24).frame(maxWidth:700,alignment:.leading).frame(maxWidth:.infinity)
    }.background(Theme.background).navigationTitle("Skill preview").navigationBarTitleDisplayMode(.inline)
      .toolbar{ToolbarItemGroup(placement:.bottomBar){if pages.count>1{
        Button("Previous page"){page=max(0,page-1)}.disabled(page==0);Spacer();Text("\(page+1) of \(pages.count)").font(.caption);Spacer();Button("Next page"){page=min(pages.count-1,page+1)}.disabled(page+1==pages.count)
      }}}
      .task(id:skill.fingerprint){
        let text=skill.content
        let result=await Task.detached(priority:.userInitiated){Self.paginate(text)}.value
        guard !Task.isCancelled else{return};pages=result;page=0
      }
  }
  private nonisolated static func paginate(_ text:String)->[String]{
    let scalars=text.unicodeScalars;var start=scalars.startIndex,result:[String]=[]
    while start<scalars.endIndex{
      let end=scalars.index(start,offsetBy:4_000,limitedBy:scalars.endIndex) ?? scalars.endIndex
      result.append(String(String.UnicodeScalarView(scalars[start..<end])));start=end
    }
    return result.isEmpty ? ["No static instructions were supplied by OpenCode."]:result
  }

}
