import OpenWorkRemoteCore
import SwiftUI

struct ModelSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var settings: ModelSettings?
  @State private var selectedID = ""
  @State private var variant = ""
  @State private var loading = false
  @State private var error: String?
  @State private var files = false
  @State private var changes = false
  private var selected: ModelOption? { settings?.models.first { $0.id == selectedID } }
  private var selection: ModelSelection? {
    selected.map { ModelSelection(providerId: $0.providerId, modelId: $0.modelId, variant: variant.isEmpty ? nil : variant) }
  }
  var body: some View {
    NavigationStack {
      Form {
        if model.selectedSession != nil {
          Section("This chat") {
            if model.host?.capabilities.artifacts == true {
              Button {files=true} label: {Label("Files from this chat",systemImage:"doc.on.doc")}
                .accessibilityIdentifier("chat-files-settings")
            }
            Button {changes=true} label: {
              Label("Workspace changes",systemImage:model.host?.capabilities.changes == true ? "doc.text.magnifyingglass" : "lock")
            }.accessibilityIdentifier("workspace-changes-settings")
          }
        }
        if loading { ProgressView("Loading models…") }
        if let error { Section { Text(error).foregroundStyle(.red); Button("Reload settings") { Task { await load() } } } }
        if let settings {
          Section {
            NavigationLink {
              ModelPickerView(models: settings.models, selection: $selectedID)
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                Text("Model").font(.caption).foregroundStyle(Theme.muted)
                Text(selected?.name ?? settings.current.modelId).font(.headline)
                Text(selected?.providerId ?? settings.current.providerId).font(.caption).foregroundStyle(Theme.muted)
              }.padding(.vertical, 6)
            }
            if let selected, !selected.variants.isEmpty {
              Picker("Reasoning", selection: $variant) {
                Text("Default").tag("")
                ForEach(selected.variants, id: \.self) { Text($0.capitalized).tag($0) }
              }
            } else { LabeledContent("Reasoning", value: "Model default") }
          } footer: { Text("Models and available reasoning levels come from OpenWork on your computer. This changes the current chat.") }
          if !model.canEditControls && !model.updatingControls {
            Section { Text("Connect and wait for this chat to finish before changing its model.").foregroundStyle(Theme.muted) }
          }
          Section {
            Button { Task { await apply() } } label: {
              HStack { Text("Apply to this chat"); if model.updatingControls { Spacer(); ProgressView() } }
            }.disabled(!model.canEditControls || selection == nil || selection == settings.current)
          } footer: { Text("Your other chats keep their model.") }
        } else if model.selectedSession == nil { Text("Open a chat to choose its model and reasoning level.") }
      }.scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Model & settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }.task(id: model.controlsScope) { await load() }
      .onChange(of: selectedID) { old, new in if old != new, selected?.variants.contains(variant) != true { variant = "" } }
      .sheet(isPresented:$files,onDismiss:{model.artifacts.closePreview()}) { ArtifactListView() }
      .sheet(isPresented:$changes,onDismiss:{model.changes.close()}) { ChangesView() }
  }
  private func load() async {
    settings = nil; error = nil
    guard model.selectedSession != nil else { return }
    loading = true; defer { loading = false }
    do {
      let value = try await model.loadModelSettings()
      settings = value
      selectedID = value.models.first { $0.providerId == value.current.providerId && $0.modelId == value.current.modelId }?.id ?? ""
      variant = value.current.variant ?? ""
    } catch { self.error = "Settings could not be loaded. Check the connection and reload." }
  }
  private func apply() async {
    guard let settings, let selection else { return }
    error = nil
    do { try await model.changeModel(selection, revision: settings.revision); await load() }
    catch { self.error = "The change could not be confirmed. Reload settings before trying again. Another client may have changed this chat." }
  }
}
private struct ModelPickerView: View {
  let models: [ModelOption]
  @Binding var selection: String
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  var body: some View {
    List(models.filter { search.isEmpty || ($0.name + " " + $0.providerId).localizedCaseInsensitiveContains(search) }) { option in
      Button { selection = option.id; dismiss() } label: {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text(option.name).foregroundStyle(Theme.ink)
            Text(option.providerId).font(.caption).foregroundStyle(Theme.muted)
          }
          Spacer()
          if selection == option.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
        }.padding(.vertical, 4)
      }
    }.searchable(text: $search, prompt: "Find a model").navigationTitle("Model")
      .scrollContentBackground(.hidden).background(Theme.background)
  }
}
