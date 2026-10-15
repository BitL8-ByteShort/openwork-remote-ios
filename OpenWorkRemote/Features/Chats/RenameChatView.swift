import OpenWorkRemoteCore
import SwiftUI

struct RenameChatView: View {
  let session: ChatSession
  let nativeReview:NativeRenameReview?
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var saving = false
  @State private var error: String?
  @State private var requestID = UUID()
  @FocusState private var focused: Bool

  init(session: ChatSession,nativeReview:NativeRenameReview?=nil) {
    self.nativeReview=nativeReview
    self.session = session
    _title = State(initialValue: session.title)
  }
  private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Chat name", text: $title, axis: .vertical)
            .focused($focused).disabled(saving).accessibilityIdentifier("chat-name")
        } footer: {
          Text("This name also appears in \(model.serviceName) on your computer.")
        }
        if trimmed.unicodeScalars.count > 200 {
          Text("Use a name with 200 characters or fewer.").foregroundStyle(.red)
        }
        if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("rename-error") } }
        if saving { ProgressView("Saving name…").accessibilityIdentifier("rename-saving") }
      }.scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Rename chat").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving && nativeReview==nil) }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { Task { await save() } }
              .disabled(saving || trimmed.isEmpty || trimmed.unicodeScalars.count > 200 || trimmed == session.title)
              .accessibilityIdentifier("save-chat-name")
          }
        }
    }.interactiveDismissDisabled(saving && nativeReview==nil)
      .onAppear { focused = true }
      .onChange(of: title) { _, _ in requestID = UUID(); error = nil }
  }
  private func save() async {
    saving = true; error = nil; focused = false
    defer { saving = false }
    do {
      if let native=model.native{
        guard let nativeReview else{throw RemoteError.unavailable}
        try await native.rename(nativeReview,title:title)
      } else {
        #if DEBUG
        try await model.rename(session, title: title, requestId: requestID)
        #else
        throw RemoteError.unavailable
        #endif
      }
      dismiss()
    }
    catch RemoteError.conflict {
      self.error = "This chat’s name changed on your computer. Your edit is kept here. Cancel and open Rename again to review the current name."
    } catch {
      self.error = "The name could not be confirmed. Your edit is kept here. Check your connection, then save again or cancel to review recent chats."
    }
  }
}
