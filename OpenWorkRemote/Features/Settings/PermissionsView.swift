import OpenWorkRemoteCore
import SwiftUI

struct PermissionsView: View {
  @Environment(AppModel.self) private var model
  @State private var access: DeviceAccess?
  @State private var permissions: SavedPermissions?
  @State private var loading = false
  @State private var error: String?
  @State private var revoke: SavedPermission?
  @State private var confirmingRevoke = false
  var body: some View {
    Form {
      if loading { ProgressView("Loading permissions…") }
      if let error { Section { Text(error).foregroundStyle(.red); Button("Reload permissions") { Task { await load() } } } }
      Section {
        if let access {
          Label(access.allWorkspaces ? "All current and future projects" : "Selected projects", systemImage: "folder")
          ForEach(model.workspaces) { Text($0.name).font(.callout) }
        }
        DisclosureGroup("Change project access") {
          Text("On your computer, open OpenWork Remote Preview → Settings → Remote access. Choose this phone, select its projects or allow all current and future projects, then save.")
            .font(.callout).foregroundStyle(Theme.muted).padding(.vertical, 8).textSelection(.enabled)
        }
      } header: { Text("This phone") } footer: { Text("Project access is approved on the computer that owns the projects.") }
      if let access {
        Section {
          grantRow("Files and attachments", allowed: access.features.fileTransfer, id: "fileTransfer")
          grantRow("Workspace settings and skills", allowed: access.features.workspaceAdministration, id: "workspaceAdministration")
          grantRow("Scheduled work", allowed: access.features.automationManagement, id: "automationManagement")
        } header: { Text("Additional access") } footer: {
          Text("Change access in OpenWork on your computer.")
        }
      }
      if let permissions {
        Section {
          Text(permissions.modeReason).font(.callout).foregroundStyle(Theme.muted)
        } header: { Text("Approval mode") }
        Section {
          if permissions.grants.isEmpty { Text("No saved tool permissions for this project.").foregroundStyle(Theme.muted) }
          ForEach(permissions.grants) { permission in
            VStack(alignment: .leading, spacing: 10) {
              Text(permission.action == "external_directory" ? "Folder access" : permission.action).font(.headline)
              Text(permission.resource).font(.callout.monospaced()).textSelection(.enabled)
              Button("Revoke saved permission", role: .destructive) { revoke = permission; confirmingRevoke = true }
                .disabled(!model.canEditControls)
            }.padding(.vertical, 8)
          }
        } header: { Text("Saved tool permissions") } footer: { Text("These permissions apply to chats in this project. Revoking removes a remembered allowance. Wait for running chats in this project to finish first.") }
      } else if model.selectedSession == nil { Section { Text("Open a chat to manage its project's saved tool permissions.") } }
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Permissions")
      .task(id: model.controlsScope) { await load() }
      .confirmationDialog("Revoke this saved permission?", isPresented: $confirmingRevoke, titleVisibility: .visible) {
        Button("Revoke permission", role: .destructive) { if let revoke { Task { await remove(revoke) } } }
        Button("Cancel", role: .cancel) { revoke = nil }
      } message: { Text(revoke.map { $0.action + "\n" + $0.resource + "\nApplies to this project's chats." } ?? "") }
  }
  private func grantRow(_ title: String, allowed: Bool, id: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      HStack(spacing: 6) {
        Image(systemName: allowed ? "checkmark" : "lock").accessibilityHidden(true)
        Text(allowed ? "Allowed" : "Not allowed")
      }.foregroundStyle(allowed ? Theme.ink : Theme.muted)
        .fixedSize(horizontal: true, vertical: true)
    }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("phone-" + id)
  }
  private func load() async {
    access = nil; permissions = nil; error = nil; loading = true
    defer { loading = false }
    do {
      access = try await model.loadDeviceAccess()
      if model.selectedSession != nil { permissions = try await model.loadSavedPermissions() }
    } catch { self.error = "Permissions could not be loaded. Check the connection and reload." }
  }
  private func remove(_ permission: SavedPermission) async {
    error = nil
    do { try await model.revokeSavedPermission(permission); revoke = nil; await load() }
    catch { self.error = "Revocation could not be confirmed. Wait for active chats to finish, then reload permissions before trying again." }
  }
}
