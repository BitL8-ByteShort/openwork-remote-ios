import OpenWorkRemoteCore
import SwiftUI

struct ChatListView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var showingSettings = false
  @State private var renaming: ChatSession?
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
          if model.uncertainCreation {
            Text("New chat creation is uncertain. Check recent chats before trying again.").font(
              .callout)
            Button("Check recent chats") { Task { await model.reviewRecentChats() } }
          }
          if results.isEmpty {
            Text(search.isEmpty ? "No chats yet." : "No matches in loaded chats.").foregroundStyle(
              Theme.muted)
          }
          ForEach(results) { s in
            Button {
              InteractionMetrics.measure("Select chat handler") { dismiss() }
              Task { await model.select(s) }
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                Text(s.title).font(.body).foregroundStyle(Theme.ink).lineLimit(2)
                if let label = s.modelLabel {
                  Text(label).font(.caption).foregroundStyle(Theme.muted)
                }
              }.padding(.vertical, 5)
            }.contextMenu {
              Button("Rename", systemImage: "pencil") { renaming = s }
                .disabled(model.connection != .ready || model.host?.capabilities.renameSession != true)
            }.accessibilityAction(named: "Rename") {
              if model.connection == .ready, model.host?.capabilities.renameSession == true { renaming = s }
            }
          }
          if model.sessionCursor != nil {
            Button("Load older chats") { Task { await model.olderSessions() } }
            Text("Search covers loaded chat titles.").font(.caption).foregroundStyle(Theme.muted)
          }
        } header: {
          Text("Recent chats")
        }
      }.scrollContentBackground(.hidden).background(Theme.background).searchable(
        text: $search, prompt: "Search chats"
      ).navigationTitle("Your chats").toolbar {
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
    }
  }
  private var results: [OpenWorkRemoteCore.ChatSession] {
    model.sessions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
  }
}
