import SwiftUI
import OpenWorkRemoteCore

struct NativeDefaultsPresentation:Identifiable{
  let id=UUID()
  let scope:NativeProjectKey
  let value:LocalChatDefaults
  let locations:[String]
}
struct NativeChatDefaultsView:View{
  let native:NativeAppCoordinator
  let scope:NativeProjectKey
  let locations:[String]
  @Environment(\.dismiss) private var dismiss
  @State private var expected:LocalChatDefaults
  @State private var choice:LocalChatDefaults
  @State private var directory:String
  @State private var models:[OpenCodeModel]=[]
  @State private var agents:[OpenCodeAgent]=[]
  @State private var loading=false
  @State private var saving=false
  @State private var notice:String?
  @State private var read=UUID()
  init(native:NativeAppCoordinator,review:NativeDefaultsPresentation){
    self.native=native;self.scope=review.scope;self.locations=review.locations
    _expected=State(initialValue:review.value);_choice=State(initialValue:review.value)
    _directory=State(initialValue:review.locations.first ?? "")
  }
  private var selected:OpenCodeModel?{models.first{model in choice.model.map{OpenCodeIdentity.matches($0.id,model.id) && OpenCodeIdentity.matches($0.providerID,model.providerID)} ?? false}}
  private var valid:Bool{
    native.projectKey==scope && native.defaults.ready && !saving && !native.defaults.busy &&
      (choice.model.map{ref in !loading && models.contains{$0.accepts(ref)}} ?? true) &&
      (choice.agent.map{id in !loading && agents.contains{$0.selectable && OpenCodeIdentity.matches($0.id,id)}} ?? true)
  }
  var body:some View{
    NavigationStack{
      Form{
        Section{Text("On this device, for new PocketWork chats in this project. Existing chats and chats created on the computer keep their settings.").font(.callout).foregroundStyle(Theme.muted)}
        if locations.count>1{
          Section{Picker("Check catalog in",selection:$directory){ForEach(Array(locations.enumerated()),id:\.offset){_,value in Text(value).tag(value)}}}
        }
        if loading{ProgressView("Checking models and agents…")}
        Section{
          NavigationLink{
            NativeModelPicker(models:models,selectedKey:selected?.selectionKey){model in
              if let value=try? OpenCodeModelRef(providerID:model.providerID,id:model.id){choice.model=value}
            }
          }label:{LabeledContent("Model",value:selected?.name ?? choice.model?.id ?? "OpenCode default")}
            .disabled(loading || models.isEmpty).accessibilityIdentifier("native-default-model")
          if let model=selected,!model.variants.isEmpty{
            Picker("Variant",selection:Binding(get:{choice.model?.isDefaultVariant==true ? "":choice.model?.variant ?? ""},set:{variant in
              if let old=choice.model,let value=try? OpenCodeModelRef(providerID:old.providerID,id:old.id,variant:variant.isEmpty ? nil:variant){choice.model=value}
            })){
              Text("Model default").tag("");ForEach(model.variants,id:\.id){Text($0.id).tag($0.id)}
              if let current=choice.model,let variant=current.variant,!current.isDefaultVariant,!model.variants.contains(where:{$0.id==variant}){Text(variant+" (unavailable)").tag(variant)}
            }
          }
          if let model=choice.model,!loading,!models.contains(where:{$0.accepts(model)}){Text("This model or variant is unavailable in the checked location. Choose another or use the OpenCode default.").font(.callout).foregroundStyle(.red)}
          Button("Use OpenCode model default"){choice.model=nil}.accessibilityIdentifier("native-default-model-reset")
        }header:{Text("New-chat model")}
        Section{
          Picker("Agent",selection:$choice.agent){
            Text("OpenCode default").tag(nil as String?)
            ForEach(agents.filter(\.selectable)){Text($0.name).tag(Optional($0.id))}
            if let old=choice.agent,!agents.contains(where:{$0.selectable && $0.id==old}){Text(old+" (unavailable)").tag(Optional(old))}
          }.accessibilityIdentifier("native-default-agent")
          Button("Use OpenCode agent default"){choice.agent=nil}
        }header:{Text("New-chat agent")}footer:{Text("Choices are checked again in the selected location before creating a chat. An unavailable choice will not silently switch models.")}
        Button("Use all OpenCode defaults"){choice=LocalChatDefaults()}.accessibilityIdentifier("native-default-reset-all")
        if let notice{Section{Text(notice).foregroundStyle(Theme.muted)}}
        if native.projectKey != scope{Text("The project or connection changed. Close this screen and reopen defaults.").foregroundStyle(.red)}
      }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("New chat defaults").navigationBarTitleDisplayMode(.inline)
        .toolbar{
          ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}.accessibilityIdentifier("native-defaults-done")}
          ToolbarItem(placement:.confirmationAction){Button("Save"){Task{await save()}}.disabled(!valid || choice==expected).accessibilityIdentifier("native-defaults-save")}
        }
    }.task(id:directory){await load()}
  }
  private func load()async{
    guard !directory.isEmpty,native.projectKey==scope,let client=native.connection.client else{return}
    let id=UUID();read=id;loading=true;notice=nil;models=[];agents=[]
    defer{if read==id{loading=false}}
    do{
      let location=OpenCodeLocation(directory:directory)
      async let catalog=client.models(location:location)
      async let registered=client.agents(location:location)
      let (models,agents)=try await(catalog,registered)
      guard read==id,native.projectKey==scope,native.connection.client === client,!Task.isCancelled else{return}
      self.models=models;self.agents=agents
    }catch{if read==id{notice="The catalog could not be loaded. Reconnect to choose a model, or clear local choices to use OpenCode defaults."}}
  }
  private func save()async{
    guard valid else{return};saving=true;defer{saving=false}
    do{try await native.defaults.set(choice,scope:scope,expected:expected);expected=choice;dismiss()}
    catch{notice="Defaults changed or could not be saved. Reopen this screen to review the current choices."}
  }
}
