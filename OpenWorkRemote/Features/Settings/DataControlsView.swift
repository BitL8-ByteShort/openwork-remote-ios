import SwiftUI

struct DataControlsView: View {
  @Environment(AppModel.self) private var model
  @State private var pending: Action?
  @State private var result: String?
  private enum Action: String, Identifiable {
    case drafts, downloads, sharing, reset
    var id: String { rawValue }
    var title: String {
      switch self {
      case .drafts: "Clear unsent drafts?"
      case .downloads: "Remove downloaded copies?"
      case .sharing:"Clear saved sharing permissions?"
      case .reset: "Reset all local data?"
      }
    }
    var button: String {
      switch self {
      case .drafts: "Clear drafts"
      case .downloads: "Remove downloads"
      case .sharing:"Clear sharing permissions"
      case .reset: "Reset local data"
      }
    }
    func explanation(native:Bool) -> String {
      if native{
        return switch self{
        case .drafts:"Remove unsent OpenCode and earlier OpenWork text, question drafts and unsent skill choices from this device. Keep unconfirmed send/action details and selected file copies. Clipboard and shared copies are not cleared. Your computer’s chats and files stay intact."
        case .downloads:"Remove this app’s OpenCode and earlier OpenWork downloaded results and preview copies. Selected attachments and copies already shared elsewhere stay. Original files on the computer stay intact."
        case .sharing:"Remove this device’s saved sharing permissions. In-progress requests are cancelled; an already submitted operation may still complete. The next send, question answer or file preparation requires another review. This does not revoke server or provider access."
        case .reset:"Remove both saved connections, local drafts and recovery text, unconfirmed actions, selected attachments, downloaded copies, sharing permissions, local groups/defaults, project visibility, last-opened chat and app preferences. Clipboard and shared copies remain outside this reset. Server tokens are not revoked. Chats, uploaded host files and work already running on the computer stay there."
        }
      }
      #if DEBUG
      return switch self {
      case .drafts: "Remove unsent chat text, question answers and skill drafts from this phone. Unconfirmed and in-progress action details and selected file copies stay until reviewed or reset. Your computer's chats stay intact."
      case .downloads: "Remove this app's downloaded results and preview copies. Selected attachments and copies already shared to another app stay. Original files on the computer stay intact."
      case .sharing:"Remove saved local sharing permissions."
      case .reset: "Remove pairing, local drafts, unfinished action records, selected attachments, downloaded copies and app preferences. This attempts to revoke the phone on your computer. If it is offline, revoke the phone there later. Your computer's chats and original files stay intact."
      }
      #else
      return "Open the native connection to review local data controls."
      #endif
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
      if let native=model.native{
        Section{NavigationLink("Recover saved draft text"){NativeDraftRecoveryView(native:native,migration:model.nativeMigration)}}
      }
      Section {
        Button("Clear unsent drafts", role: .destructive) { pending = .drafts }
          .accessibilityIdentifier("local-data-drafts")
          .disabled(!model.localStorageReady)
      } footer: {
        Text(Action.drafts.explanation(native:model.native != nil))
      }
      Section {
        Button("Remove downloaded copies", role: .destructive) { pending = .downloads }
          .accessibilityIdentifier("local-data-downloads")
      } footer: {
        Text(Action.downloads.explanation(native:model.native != nil))
      }
      if model.native != nil{
        Section{Button("Clear sharing permissions",role:.destructive){pending = .sharing}.accessibilityIdentifier("local-data-sharing")}
          footer:{Text(Action.sharing.explanation(native:true))}
      }
      Section {
        Button("Reset all local data", role: .destructive) { pending = .reset }
          .accessibilityIdentifier("local-data-reset")
      } footer: {
        Text(Action.reset.explanation(native:model.native != nil))
      }
    }.disabled(model.localDataBusy || model.isRetired)
      .scrollContentBackground(.hidden).background(Theme.background)
      .navigationTitle(model.native==nil ? "Data on this phone":"Data on this device").navigationBarTitleDisplayMode(.inline)
      .alert(pending?.title ?? "", isPresented: Binding(
        get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending
      ) { action in
        Button(action.button, role: .destructive) { Task { await perform(action) } }
        Button("Cancel", role: .cancel) {}
      } message: { action in Text(action.explanation(native:model.native != nil)) }
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
    case .sharing:
      result=await model.clearSharingPermissions() ? "Saved sharing permissions were cleared. Review the destination again before sharing." : model.notice ?? "Sharing permissions could not be cleared. Unlock this device and try again."
    case .reset:
      if await model.resetLocalData() == nil { result = model.notice ?? "Local reset could not start. Try again." }
    }
  }
}
