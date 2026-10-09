import OpenWorkRemoteCore
import SwiftUI

struct ChatSearchView: View {
  @Environment(AppModel.self) private var model
  @State private var query = ""
  var initialQuery = ""
  let onOpen: () -> Void
  var body: some View {
    List {
      Section {
        TextField("Search chat titles", text: $query).textInputAutocapitalization(.never)
          .autocorrectionDisabled().accessibilityIdentifier("older-search-query")
        Text(
          "Chat titles · "
            + (model.workspaces.first { $0.id == model.selectedWorkspace }?.name
              ?? "Selected workspace")
        ).font(.caption).foregroundStyle(Theme.muted)
      }
      if model.host?.capabilities.searchSessions != true {
        Section {
          Text(
            "Older-title search is unavailable on this computer. Update OpenWork Remote Preview or search in OpenWork on your computer."
          )
        }
      } else {
        Section {
          if model.chatSearch.loading {
            HStack {
              ProgressView()
              Text("Checking chat titles…")
            }.accessibilityIdentifier("older-search-progress")
          }
          if model.chatSearch.results.isEmpty, model.chatSearch.complete {
            Text("No matching chat titles.").foregroundStyle(Theme.muted).accessibilityIdentifier(
              "older-search-empty")
          }
          ForEach(model.chatSearch.results) { session in
            Button {
              guard let c = model.searchContext, c == model.chatSearch.context else { return }
              onOpen()
              Task { await model.openSearchResult(session, context: c) }
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                Text(session.title).foregroundStyle(Theme.ink)
                if let date = updatedDate(session.updatedAt) {
                  Text(date, style: .date).font(.caption).foregroundStyle(Theme.muted)
                }
              }.padding(.vertical, 5)
            }
            .accessibilityIdentifier("older-search-result-" + session.id)
          }
        } header: {
          Text("Found on your computer")
        }
        Section {
          if let notice = model.chatSearch.notice {
            Text(notice).foregroundStyle(Theme.muted)
            Button("Search again") { model.searchOlderTitles(query) }.disabled(
              model.chatSearch.loading)
          }
          if model.chatSearch.cursor != nil {
            Button(model.chatSearch.results.isEmpty ? "Continue search" : "Load more matches") {
              Task { await model.moreTitleMatches() }
            }.disabled(model.chatSearch.loading).accessibilityIdentifier("older-search-more")
          }
          if model.chatSearch.scanned > 0 {
            Text(
              "Checked \(model.chatSearch.scanned) chat titles"
                + (model.chatSearch.complete ? " · Search complete" : " · More titles may remain")
            ).font(.caption).foregroundStyle(Theme.muted)
          }
          Text("Search covers titles, including older chats. It does not search message content.")
            .font(.caption).foregroundStyle(Theme.muted)
        }
      }
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(
      "Search older chats"
    )
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: query) { _, value in model.searchOlderTitles(value) }
    .task(id: model.searchContext) {
      query = initialQuery
      model.searchOlderTitles(query)
    }
    .onDisappear { model.chatSearch.activate(nil) }
  }
  private func updatedDate(_ text: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: text) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: text)
  }
}
