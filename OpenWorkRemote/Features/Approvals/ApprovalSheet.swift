import OpenWorkRemoteCore
import SwiftUI

struct ApprovalBanner: View {
  let approval: Approval
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: "hand.raised").foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 3) {
          Text("Waiting for your approval").font(.callout.weight(.semibold))
          Text(approval.supportedDecisions.isEmpty ? "Review on your computer" : "Review this action").font(.caption).foregroundStyle(Theme.muted)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
      }.foregroundStyle(Theme.ink).padding(16).background(
        .orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }.accessibilityIdentifier("approval-banner")
  }
}
struct ApprovalSheet: View {
  let approval: Approval
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  private var pending: Approval? { model.approvals.first(where: { $0.id == approval.id }) }
  private var unchanged: Bool { pending?.revision == approval.revision }
  private var supported: Bool { model.host?.capabilities.replyApproval == true && approval.supportedDecisions.contains("allowOnce") && approval.supportedDecisions.contains("deny") }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Label("Approval needed", systemImage: "hand.raised").font(.title2.weight(.semibold))
          Text(
            "\(model.host?.displayName ?? "Computer") · \(model.workspaces.first(where:{$0.id==model.selectedWorkspace})?.name ?? "Workspace")"
          ).font(.callout).foregroundStyle(Theme.muted)
          Text(approval.details).font(.system(.callout, design: .monospaced)).textSelection(
            .enabled
          ).frame(maxWidth: .infinity, alignment: .leading).padding(20).background(
            Theme.surface, in: RoundedRectangle(cornerRadius: 18))
          if !unchanged {
            Label("This request has changed or was answered", systemImage: "checkmark.circle")
            Text("Close this sheet and review any current approval in the chat.").foregroundStyle(Theme.muted)
          } else if supported {
            Text("Allow this action once?").font(.headline)
            Text("Your computer keeps its existing permissions. This answer applies to the request shown above.").foregroundStyle(Theme.muted)
            if model.approvalNeedsReview(approval) {
              Text("The previous answer is unconfirmed. Check the latest request before answering again.").foregroundStyle(Theme.muted)
              Button("Check approval") { Task { await model.checkApproval(approval) } }
                .buttonStyle(PrimaryButtonStyle()).disabled(model.connection != .ready)
            } else {
              Button("Allow once") { Task { await model.replyApproval(approval, decision: "allowOnce") } }
                .buttonStyle(PrimaryButtonStyle()).disabled(model.connection != .ready)
                .accessibilityIdentifier("approval-allow-once")
              Button("Deny", role: .destructive) { Task { await model.replyApproval(approval, decision: "deny") } }
                .frame(maxWidth: .infinity, minHeight: 44).disabled(model.connection != .ready)
                .accessibilityIdentifier("approval-deny")
            }
          } else {
            Text("Continue on your computer").font(.headline)
            Text("This approval type has not been verified for phone replies. Open the same chat in OpenWork to review and answer it.").foregroundStyle(Theme.muted)
          }
          if !unchanged || !supported { Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()) }
        }.padding(24)
      }.background(Theme.background).navigationTitle("Review action").navigationBarTitleDisplayMode(
        .inline
      ).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
  }
}
