import SwiftUI

struct DataControlsView: View {
  @Environment(AppModel.self) private var model
  @State private var pending: Action?
  @State private var result: String?
  private enum Action: String, Identifiable {
    case drafts, downloads, reset
    var id: String { rawValue }
    var title: String {
      switch self {
      case .drafts: "Clear unsent drafts?"
      case .downloads: "Remove downloaded copies?"
      case .reset: "Reset all local data?"
      }
    }
    var button: String {
      switch self {
      case .drafts: "Clear drafts"
      case .downloads: "Remove downloads"
      case .reset: "Reset local data"
      }
    }
    var explanation: String {
      switch self {
      case .drafts: "Remove unsent chat text, question answers and skill drafts from this phone. Unconfirmed and in-progress action details and selected file copies stay until reviewed or reset. Your computer's chats stay intact."
      case .downloads: "Remove this app's downloaded results and preview copies. Selected attachments and copies already shared to another app stay. Original files on the computer stay intact."
      case .reset: "Remove pairing, local drafts, unfinished action records, selected attachments, downloaded copies and app preferences. This attempts to revoke the phone on your computer. If it is offline, revoke the phone there later. Your computer's chats and original files stay intact."
      }
    }
  }
  var body: some View {
    List {
      if model.localDataBusy {
        Section { ProgressView("Removing local data…") }
      }
      if let result { Section { Text(result).accessibilityIdentifier("local-data-result") } }
      if let report = model.lastResetReport {
        Section { Text(report.summary).accessibilityIdentifier("local-reset-report") }
      }
      Section {
        Button("Clear unsent drafts", role: .destructive) { pending = .drafts }
          .accessibilityIdentifier("local-data-drafts")
          .disabled(!model.localStorageReady)
      } footer: {
        Text(Action.drafts.explanation)
      }
      Section {
        Button("Remove downloaded copies", role: .destructive) { pending = .downloads }
          .accessibilityIdentifier("local-data-downloads")
      } footer: {
        Text(Action.downloads.explanation)
      }
      Section {
        Button("Reset all local data", role: .destructive) { pending = .reset }
          .accessibilityIdentifier("local-data-reset")
      } footer: {
        Text(Action.reset.explanation)
      }
    }.disabled(model.localDataBusy || model.isRetired)
      .scrollContentBackground(.hidden).background(Theme.background)
      .navigationTitle("Data on this phone").navigationBarTitleDisplayMode(.inline)
      .alert(pending?.title ?? "", isPresented: Binding(
        get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending
      ) { action in
        Button(action.button, role: .destructive) { Task { await perform(action) } }
        Button("Cancel", role: .cancel) {}
      } message: { action in Text(action.explanation) }
  }
  private func perform(_ action: Action) async {
    result = nil
    switch action {
    case .drafts:
      let cleared = await model.clearLocalDrafts()
      result = cleared ? "Unsent drafts were cleared. In-progress and unconfirmed action details and selected file copies are kept." : model.notice ?? "Drafts could not be cleared. Unlock the phone and try again."
    case .downloads:
      let cleared = await model.clearDownloadedFiles()
      result = cleared ? "Downloaded result and preview copies were removed. Original files and selected attachments are kept." : model.notice ?? "Downloaded copies could not be removed. Unlock the phone and try again."
    case .reset:
      if await model.resetLocalData() == nil { result = model.notice ?? "Local reset could not start. Try again." }
    }
  }
}
