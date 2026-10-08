import OpenWorkRemoteCore
import SwiftUI

struct CompactActivityView: View {
  let item: ConversationItem
  @State private var expanded = false
  private var running: Bool { item.messages.contains { $0.state == "streaming" } }
  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(item.messages) { MessageView(message: $0) }
      }.padding(.top, 8)
    } label: {
      HStack(spacing: 8) {
        if running { ProgressView().controlSize(.small) }
        Text("Activity").fontWeight(.medium)
        Text("· \(item.toolCount) \(item.toolCount == 1 ? "step" : "steps")")
        if item.messages.contains(where: { $0.state == "error" }) { Image(systemName: "exclamationmark.circle") }
      }.font(.caption).foregroundStyle(Theme.muted).frame(minHeight: 24)
    }.padding(.horizontal, 14).padding(.vertical, 10)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
      .accessibilityIdentifier("compact-tool-activity")
  }
}
