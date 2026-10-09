import OpenWorkRemoteCore
import SwiftUI

struct ChatListView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var showingSettings = false
  @State private var renaming: ChatSession?
  @State private var chatAction: ChatActionRequest?
  @State private var naming: GroupNameRequest?
  @State private var moving: MoveChatRequest?
  @State private var managingGroups = false
  @State private var groupFilter: String?
  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(model.workspaces) { w in
            Button {
              Task { await model.changeWorkspace(w) }
            } label: {
              HStack {
                Image(systemName: "folder")
                Text(w.name)
                Spacer()
                if w.id == model.selectedWorkspace {
                  Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
              }.foregroundStyle(Theme.ink)
            }
          }
        } header: {
          Text("Workspaces")
        }
        Section {
          Button { managingGroups = true } label: {
            Label("Manage groups", systemImage: model.host?.capabilities.sessionGroups == true ? "folder.badge.gearshape" : "lock")
          }.accessibilityIdentifier("groups-manage")
          if model.host?.capabilities.sessionGroups == true {
            GroupStatus()
            if let snapshot = model.groups.snapshot {
              ScrollView(.horizontal) {
                HStack(spacing: 8) {
                  filterChoice("All chats", nil)
                  ForEach(snapshot.groups) { group in filterChoice(group.label, group.id) }
                  filterChoice("No group", "")
                }
              }
            }
          }
        } header: { Text("Groups") }
        if model.uncertainCreation {
          Section {
            Text("New chat creation is uncertain. Check recent chats before trying again.").font(.callout)
            Button("Check recent chats") { Task { await model.reviewRecentChats() } }
          }
        }
        if let snapshot = model.groups.snapshot {
          ForEach(snapshot.groups.filter { groupFilter == nil || groupFilter == $0.id }) { group in
            Section {
              let chats = results.filter { snapshot.assignments[$0.id] == group.id }
              if chats.isEmpty { Text("No loaded chats in this group.").foregroundStyle(Theme.muted) }
              ForEach(chats) { chatRow($0) }
            } header: { Text(group.label) }
          }
          if groupFilter == nil || groupFilter == "" {
            Section {
              let chats = results.filter { snapshot.assignments[$0.id] == nil }
              if chats.isEmpty { Text("No loaded chats outside groups.").foregroundStyle(Theme.muted) }
              ForEach(chats) { chatRow($0) }
            } header: { Text("No group") }
          }
        } else {
          Section {
            if results.isEmpty { Text(search.isEmpty ? "No chats yet." : "No matches in loaded chats.").foregroundStyle(Theme.muted) }
            ForEach(results) { chatRow($0) }
          } header: { Text("Recent chats") }
        }
        if model.sessionCursor != nil {
          Section {
            Button("Load older chats") { Task { await model.olderSessions() } }
            Text("Search covers loaded chat titles.").font(.caption).foregroundStyle(Theme.muted)
          }
        }
      }.scrollContentBackground(.hidden).background(Theme.background).searchable(
        text: $search, prompt: "Search chats"
      ).navigationTitle("Your chats").toolbar {
        ToolbarItem(placement: .bottomBar) {
          Button { naming = GroupNameRequest(id: "new", group: nil, revision: model.groups.snapshot?.revision, context: model.groupContext) } label: {
            Label("New group", systemImage: "folder.badge.plus")
          }.disabled(!model.groups.canEdit).accessibilityIdentifier("groups-new")
        }
        ToolbarItem(placement: .bottomBar) {
          Button { InteractionMetrics.measure("Open settings handler") { showingSettings = true } } label: {
            Label("Settings", systemImage: "gearshape")
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { InteractionMetrics.measure("Dismiss history handler") { dismiss() } }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task {
              await model.createChat()
              if model.selectedSession != nil { dismiss() }
            }
          } label: {
            Image(systemName: "square.and.pencil")
          }.disabled(
            model.connection != .ready || model.host?.capabilities.createSession != true
              || model.loading || model.uncertainCreation
          ).accessibilityLabel("New chat")
        }
      }.sheet(isPresented: $showingSettings) { ConnectionView() }
        .sheet(item: $renaming) { RenameChatView(session: $0) }
        .sheet(item: $chatAction) { request in ChatActionView(request: request, onComplete: { if request.action != .delete { dismiss() } }) }
        .sheet(item: $naming) { GroupNameEditor(group: $0.group, expectedRevision: $0.revision, expectedContext: $0.context) }
        .sheet(item: $moving) { MoveChatView(session: $0.session, expectedRevision: $0.revision, expectedContext: $0.context) }
        .sheet(isPresented: $managingGroups) { GroupEditor() }
        .task(id: model.groupRefreshID) {
          while !Task.isCancelled {
            await model.refreshGroups()
            do { try await Task.sleep(for: .seconds(6)) } catch { break }
          }
        }
        .onChange(of: model.groups.snapshot?.groups.map(\.id)) { _, ids in
          if let filter = groupFilter, !filter.isEmpty, !(ids?.contains(filter) ?? false) { groupFilter = "" }
        }
    }
  }
  private func filterChoice(_ label: String, _ id: String?) -> some View {
    Button { groupFilter = id } label: { Text(label).padding(.horizontal, 12).padding(.vertical, 8) }
      .background(groupFilter == id ? Theme.surface : Theme.background, in: Capsule())
      .foregroundStyle(Theme.ink).accessibilityIdentifier("group-filter-" + (id ?? "all"))
      .accessibilityAddTraits(groupFilter == id ? .isSelected : [])
  }
  private func chatRow(_ session: ChatSession) -> some View {
    Button {
      InteractionMetrics.measure("Select chat handler") { dismiss() }
      Task { await model.select(session) }
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Text(session.title).font(.body).foregroundStyle(Theme.ink).lineLimit(2)
        if let label = session.modelLabel { Text(label).font(.caption).foregroundStyle(Theme.muted) }
      }.padding(.vertical, 5)
    }.contextMenu {
      Button("Rename", systemImage: "pencil") { renaming = session }
        .disabled(model.connection != .ready || model.host?.capabilities.renameSession != true)
      Button("Move to group", systemImage: "folder") { moveChat(session) }.disabled(!model.groups.canEdit)
      Button("Continue in a new chat", systemImage: "arrow.triangle.branch") { action(session, .fork(beforeMessageId:nil)) }.disabled(model.connection != .ready || model.host?.capabilities.forkSession != true)
      Button("Delete chat", systemImage: "trash", role: .destructive) { action(session, .delete) }.disabled(model.connection != .ready || model.host?.capabilities.deleteSession != true)
    }.accessibilityAction(named: "Rename") {
      if model.connection == .ready, model.host?.capabilities.renameSession == true { renaming = session }
    }.accessibilityAction(named: "Move to group") { moveChat(session) }
      .accessibilityAction(named: "Continue in a new chat") { action(session,.fork(beforeMessageId:nil)) }
      .accessibilityAction(named: "Delete chat") { action(session,.delete) }
  }
  private func action(_ session:ChatSession,_ action:SessionAction) {
    guard model.connection == .ready,model.host?.capabilities.forkSession == true,model.host?.capabilities.deleteSession == true,let context=model.actionContext(for:session) else{return}
    chatAction=ChatActionRequest(session:session,action:action,context:context)
  }
  private func moveChat(_ session: ChatSession) {
    guard model.groups.canEdit else { return }
    moving = MoveChatRequest(session: session, revision: model.groups.snapshot?.revision, context: model.groupContext)
  }
  private var results: [OpenWorkRemoteCore.ChatSession] {
    model.sessions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
  }
}
