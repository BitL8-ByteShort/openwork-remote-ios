import OpenWorkRemoteCore
import SwiftUI

struct MessageView: View {
  let message: ChatMessage
  @Environment(AppModel.self) private var model
  @State private var chatAction:ChatActionRequest?
  @State private var copied = false
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if message.role == "user" {
        HStack {
          Spacer(minLength: 42)
          Text(message.blocks.compactMap(\.text).joined(separator: "\n")).font(.body).lineSpacing(4)
            .textSelection(.enabled).padding(18).background(
              Theme.surface, in: RoundedRectangle(cornerRadius: 24))
        }
      } else {
        if message.role == "assistant" {
          HStack(spacing: 10) {
            BrandMark(size: 26)
            Text("OpenWork").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
          }.frame(minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine).padding(.bottom, 4)
        }
        ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
          switch block.kind {
          case "text": MarkdownView(text: block.text ?? "")
          case "code": CodeBlockView(text: block.text ?? "", language: block.language)
          case "tool": ToolActivityView(block: block)
          default:
            Label(block.label ?? "Content available on computer", systemImage: "desktopcomputer")
              .font(.callout).foregroundStyle(Theme.muted)
          }
        }
        if message.state == "error" {
          Label(
            "The task ended with an error. Check your computer for details.",
            systemImage: "exclamationmark.circle"
          ).font(.callout).foregroundStyle(.red)
        }
        if message.state == "cancelled" {
          Label("Response stopped", systemImage: "stop.circle").font(.callout).foregroundStyle(Theme.muted)
        }
        if message.state == "streaming" {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Working…").font(.caption).foregroundStyle(Theme.muted)
          }
        } else if message.role == "assistant" {
          Button {
            UIPasteboard.general.string = message.blocks.compactMap(\.text).joined(
              separator: "\n\n")
            copied = true
          } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(Theme.muted)
              .frame(width: 44, height: 44, alignment: .leading)
          }.accessibilityLabel(copied ? "Message copied" : "Copy message")
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
      .contextMenu {
        Button("Fork before this message",systemImage:"arrow.triangle.branch") { forkBefore() }
          .disabled(model.connection != .ready || model.host?.capabilities.forkSession != true || message.state == "streaming")
      }.accessibilityAction(named:"Fork before this message") { forkBefore() }
      .sheet(item:$chatAction) { ChatActionView(request:$0) }
  }
  private func forkBefore() {
    guard model.connection == .ready,model.host?.capabilities.forkSession == true,let session=model.selectedSession,let context=model.actionContext(for:session),message.state != "streaming" else{return}
    chatAction=ChatActionRequest(session:session,action:.fork(beforeMessageId:message.id),context:context)

  }
}
struct ToolActivityView: View {
  let block: MessageBlock
  var body: some View {
    DisclosureGroup {
      Text(block.summary ?? "Tool activity on your computer.").font(.callout).foregroundStyle(
        Theme.muted
      ).padding(.top, 8)
    } label: {
      Label(block.name ?? "Tool activity", systemImage: "wrench.and.screwdriver").font(
        .callout.weight(.medium))
    }.padding(16).background(Theme.raised, in: RoundedRectangle(cornerRadius: 18)).overlay(
      RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
  }
}
