import OpenWorkRemoteCore
import SwiftUI

struct GroupNameRequest: Identifiable {
  let id: String
  let group: SessionGroup?
  let revision: String?
  let context: GroupContext?
}
struct GroupNameEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let group: SessionGroup?
  let expectedRevision: String?
  let expectedContext: GroupContext?
  @State private var context: GroupContext?
  @State private var revision: String?
  @State private var name = ""
  var body: some View {
    NavigationStack {
      Form {
        Text(model.workspaces.first { $0.id == model.selectedWorkspace }?.name ?? "Workspace").font(
          .caption
        ).foregroundStyle(Theme.muted)
        TextField("Group name", text: $name).accessibilityIdentifier("group-name")
        if let notice = model.groups.notice { Text(notice).foregroundStyle(Theme.muted) }
        Button("Refresh and review groups") {
          Task {
            await model.refreshGroups()
            revision = model.groups.snapshot?.revision
            context = model.groupContext
          }
        }
        Text("Changes the group name in this workspace.").font(.caption).foregroundStyle(
          Theme.muted)
      }.scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle(group == nil ? "New group" : "Rename group")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.accessibilityIdentifier("group-name-cancel")
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(group == nil ? "Create group" : "Save name") {
              let action: GroupAction =
                group.map { .rename(id: $0.id, label: name) } ?? .create(label: name)
              Task {
                if await model.changeGroup(
                  action, expectedRevision: revision, expectedContext: context)
                {
                  dismiss()
                }
              }
            }.disabled(!model.groups.canEdit || (try? SessionGroup.label(name)) == nil)
              .accessibilityIdentifier("group-name-save")
          }
        }
    }.onAppear {
      name = group?.label ?? ""
      revision = expectedRevision
      context = expectedContext
    }
  }
}
struct GroupStatus: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    if model.host?.capabilities.sessionGroups != true {
      Label(
        "Group controls are unavailable on this computer. Update OpenWork Remote Preview or manage groups on your computer.",
        systemImage: "lock"
      ).foregroundStyle(Theme.muted)
    } else if model.groups.loading && model.groups.snapshot == nil {
      ForEach(0..<3, id: \.self) { _ in
        RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface).frame(height: 44).redacted(
          reason: .placeholder
        ).accessibilityHidden(true)
      }
    }
    if let notice = model.groups.notice { Text(notice).foregroundStyle(Theme.muted) }
    if model.groups.pending?.phase == .uncertain {
      Text(
        "The earlier change may already be applied. Refresh, review the groups, then keep the computer’s current groups."
      ).font(.callout).foregroundStyle(Theme.muted)
      Button("Keep current groups") {
        guard let c = model.groupContext else { return }
        Task { try? await model.groups.keepCurrentGroups(context: c) }
      }.disabled(!model.groups.canKeepCurrentGroups)
    }
  }
}
struct GroupEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var naming: GroupNameRequest?
  @State private var removing: GroupNameRequest?
  var body: some View {
    NavigationStack {
      List {
        Section { GroupStatus() }
        if let snapshot = model.groups.snapshot {
          ForEach(Array(snapshot.groups.enumerated()), id: \.element.id) { index, group in
            HStack {
              Button(group.label) {
                naming = GroupNameRequest(
                  id: group.id, group: group, revision: snapshot.revision,
                  context: model.groupContext)
              }.foregroundStyle(Theme.ink).accessibilityIdentifier("group-edit-" + group.id)
              Spacer()
              Button {
                move(index, -1)
              } label: {
                Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44)
              }.disabled(index == 0 || !model.groups.canEdit).accessibilityLabel(
                "Move \(group.label) up")
              Button {
                move(index, 1)
              } label: {
                Image(systemName: "arrow.down").frame(minWidth: 44, minHeight: 44)
              }.disabled(index == snapshot.groups.count - 1 || !model.groups.canEdit)
                .accessibilityLabel("Move \(group.label) down")
              Button(role: .destructive) {
                removing = GroupNameRequest(
                  id: group.id, group: group, revision: snapshot.revision,
                  context: model.groupContext)
              } label: {
                Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
              }.disabled(!model.groups.canEdit).accessibilityLabel("Remove \(group.label)")
                .accessibilityIdentifier("group-remove-" + group.id)
            }.buttonStyle(.borderless)
          }
          if snapshot.groups.isEmpty { Text("No groups yet.").foregroundStyle(Theme.muted) }
        }
        Button("New group") {
          naming = GroupNameRequest(
            id: "new", group: nil, revision: model.groups.snapshot?.revision,
            context: model.groupContext)
        }.disabled(!model.groups.canEdit)
        Button("Refresh groups") { Task { await model.refreshGroups() } }
      }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Chat groups")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("groups-manage-done")
          }
        }
        .sheet(item: $naming) {
          GroupNameEditor(
            group: $0.group, expectedRevision: $0.revision, expectedContext: $0.context)
        }
        .alert(
          "Remove \(removing?.group?.label ?? "group")?",
          isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
          Button("Cancel", role: .cancel) { removing = nil }
          Button("Remove group", role: .destructive) {
            guard let request = removing, let group = request.group else { return }
            removing = nil
            Task {
              _ = await model.changeGroup(
                .remove(id: group.id), expectedRevision: request.revision,
                expectedContext: request.context)
            }
          }
        } message: {
          Text("Its chats move to No group. The chats are kept.")
        }
    }.task(id: model.groupRefreshID) { await model.refreshGroups() }
  }
  private func move(_ index: Int, _ offset: Int) {
    guard let groups = model.groups.snapshot?.groups, groups.indices.contains(index + offset) else {
      return
    }
    let revision = model.groups.snapshot?.revision
    let context = model.groupContext
    var ids = groups.map(\.id)
    ids.swapAt(index, index + offset)
    Task {
      _ = await model.changeGroup(
        .reorder(ids: ids), expectedRevision: revision, expectedContext: context)
    }
  }
}
struct MoveChatRequest: Identifiable {
  var id: String { session.id }
  let session: ChatSession
  let revision: String?
  let context: GroupContext?
}
struct MoveChatView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let session: ChatSession
  let expectedRevision: String?
  let expectedContext: GroupContext?
  @State private var context: GroupContext?
  @State private var revision: String?
  @State private var selected: String?
  @State private var naming = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.rowGap) {
          Text(model.workspaces.first { $0.id == session.workspaceId }?.name ?? "Workspace").font(
            .caption
          ).foregroundStyle(Theme.muted)
          Text(session.title).font(.callout).foregroundStyle(Theme.muted)
          Text("A place for this conversation.").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
          Text("Choose a group in this workspace, or keep the chat outside a group.")
            .foregroundStyle(Theme.muted)
          GroupStatus()
          if let groups = model.groups.snapshot?.groups {
            ForEach(groups) { group in choice(group.label, group.id) }
            choice("No group", nil)
          }
          Button("Refresh and review groups") {
            Task {
              await model.refreshGroups()
              revision = model.groups.snapshot?.revision
              context = model.groupContext
              if let selected,
                !((model.groups.snapshot?.groups.contains { $0.id == selected }) ?? false)
              {
                self.selected = nil
              }
            }
          }
          Button("New group") { naming = true }.disabled(!model.groups.canEdit)
        }.padding(24)
      }.background(Theme.background).navigationTitle("Move chat").navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.accessibilityIdentifier("move-chat-cancel")
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button("Move chat") {
          Task {
            if await model.changeGroup(
              .assign(sessionId: session.id, groupId: selected), expectedRevision: revision,
              expectedContext: context)
            {
              dismiss()
            }
          }
        }.buttonStyle(PrimaryButtonStyle()).disabled(
          !model.groups.canEdit || session.workspaceId != model.selectedWorkspace
        ).accessibilityIdentifier("move-chat-save").padding()
      }
      .sheet(isPresented: $naming) {
        GroupNameEditor(
          group: nil, expectedRevision: model.groups.snapshot?.revision,
          expectedContext: model.groupContext)
      }
    }.onAppear {
      selected = model.groups.snapshot?.assignments[session.id]
      revision = expectedRevision
      context = expectedContext
    }
    .task(id: model.groupRefreshID) { await model.refreshGroups() }
  }
  private func choice(_ label: String, _ id: String?) -> some View {
    Button {
      selected = id
    } label: {
      HStack {
        Text(label)
        Spacer()
        if selected == id { Image(systemName: "checkmark") }
      }.padding().frame(maxWidth: .infinity).background(
        selected == id ? Theme.surface : Theme.background,
        in: RoundedRectangle(cornerRadius: Theme.radius))
    }.foregroundStyle(Theme.ink).disabled(!model.groups.canEdit).accessibilityIdentifier(
      "move-group-" + (id ?? "none")
    ).accessibilityAddTraits(selected == id ? .isSelected : [])
  }
}
