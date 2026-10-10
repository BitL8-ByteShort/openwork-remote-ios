import SwiftUI
import OpenWorkRemoteCore
struct WorkspaceSettingsView:View {
 @Environment(AppModel.self) private var model
 var body:some View {
  List {
   Section {Text("Workspace changes affect OpenWork on your computer. Administration access is required.").foregroundStyle(Theme.muted)} header:{Text(model.workspaces.first{$0.id==model.selectedWorkspace}?.name ?? "Workspace")}
   Section {NavigationLink {WorkspaceDefaultsView()} label:{VStack(alignment:.leading,spacing:6){Text("Defaults").font(.headline);Text("Model and reasoning for new chats").font(.caption).foregroundStyle(Theme.muted)}.padding(.vertical,6)}.accessibilityIdentifier("workspace-defaults-open")}
   Section {NavigationLink{SkillListView()}label:{VStack(alignment:.leading,spacing:6){Text("Skills").font(.headline);Text("Instructions for this workspace").font(.caption).foregroundStyle(Theme.muted)}.padding(.vertical,6)}.accessibilityIdentifier("workspace-skills-open")}
   Section {Text("Phone access is managed on your computer. Tool approval rules remain in OpenWork.").font(.callout).foregroundStyle(Theme.muted)}
  }.navigationTitle("Workspace").navigationBarTitleDisplayMode(.inline).scrollContentBackground(.hidden).background(Theme.background)
 }
}
struct WorkspaceDefaultsView:View {
 @Environment(AppModel.self) private var model
 @State private var selectedID=""
 @State private var variant=""
 @State private var formRevision:String?
 @State private var formContext:WorkspaceDefaultsContext?
 private var store:WorkspaceDefaultsStore{model.workspaceDefaults}
 private var selected:ModelOption?{store.snapshot?.models.first{$0.id==selectedID}}
 private var selection:ModelSelection?{selected.map{ModelSelection(providerId:$0.providerId,modelId:$0.modelId,variant:variant.isEmpty ? nil:variant)}}
 var body:some View {
  Form {
   Section {Text("This default affects new chats in this workspace. Existing chats keep their model.").accessibilityIdentifier("workspace-defaults-scope")}
   if store.loading {ProgressView("Checking workspace defaults…")}
   if let notice=store.notice {Section {Text(notice).foregroundStyle(Theme.muted).accessibilityIdentifier("workspace-defaults-notice")}}
   if let snapshot=store.snapshot {
    Section("Current default") {Text(currentLabel(snapshot)).accessibilityIdentifier("workspace-defaults-current")}
    Section("New-chat default") {
     NavigationLink {ModelPickerView(models:snapshot.models,selection:$selectedID)} label:{VStack(alignment:.leading,spacing:6){Text(selected?.name ?? "Choose a model").font(.headline);if let selected{Text(selected.providerId).font(.caption).foregroundStyle(Theme.muted)}}}.accessibilityIdentifier("workspace-defaults-model")
     if let selected,!selected.variants.isEmpty {Picker("Reasoning",selection:$variant){Text("Model default").tag("");ForEach(selected.variants,id:\.self){Text($0.capitalized).tag($0)}}}else{LabeledContent("Reasoning",value:"Model default")}
    }.disabled(!store.canEdit)
    Section {
     Button {Task{await save()}} label:{HStack{Text("Save for new chats");if store.saving{Spacer();ProgressView()}}}.disabled(!store.canEdit || selection==nil || selection==snapshot.current || formContext != store.context || formRevision != snapshot.revision).accessibilityIdentifier("workspace-defaults-save")
     if store.canKeepCurrent {Button("Keep current default"){Task{guard let c=store.context else{return};do{try await store.keepCurrent(context:c);useCurrent()}catch{}}}.accessibilityIdentifier("workspace-defaults-keep-current")}
     else if formRevision != snapshot.revision,store.pending==nil {Button("Use current default"){useCurrent()}.accessibilityIdentifier("workspace-defaults-review")}
    } footer:{Text("Saving changes this workspace only. It does not change provider accounts or tool permissions.")}
   }else if !store.loading,store.notice==nil {
    Section {Text(model.connection == .ready ? "Default model editing is unavailable on this computer. Update OpenWork Remote Preview or change it in OpenWork on your computer.":"Reconnect to check this workspace’s defaults.").foregroundStyle(Theme.muted)}
   }
   Section {Button("Refresh current default"){Task{await model.refreshWorkspaceDefaults();if formRevision==nil{useCurrent()}}}.disabled(store.saving).accessibilityIdentifier("workspace-defaults-refresh")}
  }.navigationTitle("Workspace defaults").navigationBarTitleDisplayMode(.inline).scrollContentBackground(.hidden).background(Theme.background)
   .task(id:model.defaultsRefreshID){if formContext != model.workspaceDefaultsContext {formRevision=nil;formContext=nil;selectedID="";variant=""};await model.refreshWorkspaceDefaults();if formRevision==nil{useCurrent()}}
   .onChange(of:selectedID){_,_ in if selected?.variants.contains(variant) != true{variant=""}}
 }
 private func currentLabel(_ snapshot:WorkspaceDefaults)->String {
  guard let c=snapshot.current else{return "No model default assigned"}
  let name=snapshot.models.first{$0.providerId==c.providerId && $0.modelId==c.modelId}?.name ?? c.modelId
  return name+(c.variant.map{" · "+$0.capitalized} ?? "")
 }
 private func useCurrent(){guard let snapshot=store.snapshot,let context=store.context else{return};formRevision=snapshot.revision;formContext=context;selectedID=snapshot.current.flatMap{c in snapshot.models.first{$0.providerId==c.providerId && $0.modelId==c.modelId}?.id} ?? "";variant=snapshot.current?.variant ?? ""}
 private func save()async{guard let selection,let revision=formRevision,let c=formContext else{return};if await model.saveWorkspaceDefaults(selection,revision:revision,context:c){useCurrent()}}
}
