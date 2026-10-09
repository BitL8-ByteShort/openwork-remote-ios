import OpenWorkRemoteCore
import SwiftUI

struct ChatActionRequest: Identifiable {
  let id = UUID()
  let session: ChatSession
  let action: SessionAction
  let context: ChatActionContext
}
struct ChatActionView: View {
  let request: ChatActionRequest
  var onComplete: (() -> Void)?
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var revision: String?
  @State private var localError: String?
  private var deleting: Bool { request.action == .delete }
  private var heading: String {
    deleting
      ? "Delete chat"
      : request.action == .fork(beforeMessageId: nil)
        ? "Continue in a new chat" : "Fork before this message"
  }
  private var matching: Bool {
    model.actionContext(for: request.session) == request.context
      && model.chatActions.context == request.context
  }
  private var store: ChatActionStore { model.chatActions }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Image(systemName: deleting ? "trash" : "arrow.triangle.branch").font(.title)
            .foregroundStyle(deleting ? Color.red : Theme.accent)
          Text(deleting ? "Delete “\(store.preview?.title ?? request.session.title)”?" : heading)
            .font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
          Text(
            deleting
              ? "This permanently removes this chat and its history from OpenWork on your computer. It cannot be undone here."
              : request.action == .fork(beforeMessageId: nil)
                ? "Copy this conversation into a new chat with the same model and settings. Your original chat and its files stay intact."
                : "Create a new chat with the messages before this one. This message and everything after it are excluded. Your original chat stays intact."
          ).foregroundStyle(Theme.muted)
          if deleting {
            Text(
              "Files remain on your computer. Linked subchats block deletion from the phone. Keep this chat idle on your computer until deletion finishes."
            )
            .font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
              Theme.surface, in: RoundedRectangle(cornerRadius: 20))
          }
          if !matching {
            Text(
              "The connection or workspace changed. Close this screen and open the action again."
            ).foregroundStyle(Theme.muted)
          } else if store.loading {
            ProgressView("Checking this chat…").accessibilityIdentifier("chat-action-loading")
          } else if let p = store.preview, p.running {
            Text("This chat is running. Stop it on your computer, then refresh before continuing.")
              .foregroundStyle(Theme.muted)
          } else if deleting, store.preview?.deleteReason == "linkedChats" {
            Text("This chat has linked subchats. Review and delete it on your computer.")
              .foregroundStyle(Theme.muted).accessibilityIdentifier("chat-action-linked")
          }
          if let notice = store.notice, matching {
            Text(notice).font(.callout).foregroundStyle(Theme.muted).accessibilityIdentifier(
              "chat-action-notice")
          }
          if let localError { Text(localError).font(.callout).foregroundStyle(.red) }
          if matching, store.pending?.phase == .uncertain {
            Button("Check recent chats") {
              Task {
                await model.reviewChatAction(session: request.session, context: request.context)
              }
            }.accessibilityIdentifier("chat-action-review")
            if store.reviewed {
              ForEach(store.reviewedChats.prefix(5)) { chat in
                Text(chat.title).font(.callout).foregroundStyle(Theme.ink)
              }
              Text(
                "Review these recent chats or the computer before dismissing this saved uncertainty. This does not confirm that the action succeeded."
              ).font(.caption).foregroundStyle(Theme.muted)
              Button("Keep current chats") {
                Task {
                  do {
                    try await store.keepCurrentChats(context: request.context)
                    dismiss()
                  } catch { localError = "The saved action could not be cleared safely." }
                }
              }.accessibilityIdentifier("chat-action-keep-current")
            }
          } else {
            Button {
              Task { await confirm() }
            } label: {
              HStack {
                if store.saving, matching { ProgressView().tint(.white) }
                Text(deleting ? "Delete this chat" : "Create new chat")
              }.frame(maxWidth: .infinity)
            }.buttonStyle(
              PrimaryButtonStyle(
                fill: deleting ? Color(red: 0.71, green: 0.23, blue: 0.21) : Theme.accent,
                ink: deleting ? .white : Theme.onAccent)
            )
            .disabled(
              !matching || model.connection != .ready || !store.canAct || revision == nil
                || (deleting
                  ? store.preview?.deleteAvailable != true : store.preview?.forkAvailable != true)
            )
            .accessibilityIdentifier("chat-action-confirm")
          }
          if matching, !store.saving, store.pending == nil {
            Button("Refresh chat") { Task { await refresh() } }.accessibilityIdentifier(
              "chat-action-refresh")
          }
        }.padding(24)
      }.background(Theme.background).navigationTitle(heading).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(deleting ? "Keep chat" : "Cancel") { dismiss() }.accessibilityIdentifier(
              "chat-action-cancel")
          }
        }
    }.task { await refresh() }
  }
  private func refresh() async {
    revision = nil
    await model.refreshChatAction(session: request.session, context: request.context)
    guard matching else { return }
    revision = store.preview?.revision
  }
  private func confirm() async {
    guard matching, let revision else { return }
    if await model.performChatAction(
      request.action, session: request.session, context: request.context, revision: revision)
    {
      dismiss()
      onComplete?()
    }
  }
}
