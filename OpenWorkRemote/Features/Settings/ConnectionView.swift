import SwiftUI

struct ConnectionView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @AppStorage("appearance") private var appearance = "system"
  @AppStorage("compactToolActivity") private var compactToolActivity = true
  @State private var confirmingForget = false
  @State private var showingModelSettings = false
  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 14) {
            Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 5) {
              Text(model.host?.displayName ?? "Your computer").font(.headline)
              Label(
                model.connection.label,
                systemImage: model.connection == .ready ? "checkmark.circle.fill" : "circle.dotted"
              ).font(.caption).foregroundStyle(model.connection == .ready ? .green : Theme.muted)
            }
          }.padding(.vertical, 8)
          if let h = model.host {
            LabeledContent("OpenWork", value: h.upstreamVersion)
            LabeledContent("Computer", value: h.platform == "macos" ? "macOS" : "Linux")
          }
          Button("Reconnect") { model.connect() }
        } header: {
          Text("Paired computer")
        }
        Section {
          ForEach(model.workspaces) { w in Label(w.name, systemImage: "folder") }
        } header: {
          Text("Allowed workspaces")
        }
        Section {
          NavigationLink("Permissions") { PermissionsView() }
          Button("Model & settings") { showingModelSettings = true }
            .disabled(model.selectedSession == nil || model.host?.capabilities.modelSettings != true)
          Toggle("Compact tool activity", isOn: $compactToolActivity)
        } header: {
          Text("Conversation")
        } footer: {
          Text("Group tool calls into an expandable Activity row. Required approvals always stay visible.")
        }
        Section {
          Picker("Appearance", selection: $appearance) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
          }
        } header: {
          Text("Appearance")
        }
        Section {
          Text(
            "Keep OpenWork running with Remote access enabled on your computer. Both devices need Tailscale. Replies continue on the computer while this app is closed."
          ).font(.callout).foregroundStyle(Theme.muted)
          Text("Verified folder-access requests can be answered here. Other approval types are handled in OpenWork on your computer.").font(.callout)
            .foregroundStyle(Theme.muted)
        }
        Section {
          Button("Forget this computer", role: .destructive) { confirmingForget = true }
        } footer: {
          Text("Your drafts stay on this phone, separated by computer and chat.")
        }
      }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Settings")
        .sheet(isPresented: $showingModelSettings) { ModelSettingsView() }
        .navigationBarTitleDisplayMode(.inline).toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }.confirmationDialog(
          "Forget this computer?", isPresented: $confirmingForget, titleVisibility: .visible
        ) {
          Button("Forget computer", role: .destructive) {
            Task {
              await model.forget()
              dismiss()
            }
          }
        } message: {
          Text(
            "This removes the phone’s saved credential. If your computer is offline, also revoke this phone in OpenWork’s Remote access settings when it is online."
          )
        }
    }
  }
}
