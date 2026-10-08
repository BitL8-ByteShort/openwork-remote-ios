import OpenWorkRemoteCore
import SwiftUI

private enum ChatSheet: String, Identifiable {
  case chats, settings, model
  var id: String { rawValue }
}
struct ChatView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var sheet: ChatSheet?
  @State private var approval: Approval?
  @State private var nearBottom = true
  @State private var newReplies = false
  @AppStorage("compactToolActivity") private var compactToolActivity = true
  var body: some View {
    VStack(spacing: 0) {
      header
      if model.connection != .ready {
        HStack {
          if model.connection == .reconnecting || model.connection == .connecting {
            ProgressView().controlSize(.small)
          }
          Text(model.connection.label).font(.caption)
          Spacer()
          Button(model.connection == .revoked ? "Pair again" : "Reconnect") { model.connect() }.font(.caption.weight(.semibold)).frame(
            minHeight: 44)
        }.padding(.horizontal, 24).background(Theme.surface)
      }
      if let notice = model.notice, !model.uncertain {
        HStack(alignment: .top) {
          Image(systemName: "info.circle")
          Text(notice).font(.callout)
          Spacer()
          Button {
            model.notice = nil
          } label: {
            Image(systemName: "xmark").frame(width: 44, height: 44)
          }
        }.padding(.leading, 24).foregroundStyle(Theme.muted)
      }
      if let first = model.approvals.first {
        ApprovalBanner(approval: first) { approval = first }.padding(.horizontal, 24).padding(
          .top, 12)
      }
      if model.status?.phase == "error" {
        Label("The model could not finish. Check its setup in OpenWork on your computer.", systemImage: "exclamationmark.circle")
          .font(.callout).foregroundStyle(Theme.muted).padding(.horizontal, 24).padding(.vertical, 12)
      }
      if model.loading {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.selectedSession == nil {
        empty
      } else {
        conversation
      }
      ComposerView()
    }.background(Theme.background).foregroundStyle(Theme.ink).sheet(item: $sheet) {
      switch $0 {
      case .chats: ChatListView()
      case .settings: ConnectionView()
      case .model: ModelSettingsView()
      }
    }.sheet(item: $approval) { ApprovalSheet(approval: $0) }.toolbar(.hidden, for: .navigationBar)
  }
  private var header: some View {
    HStack {
      Button {
        sheet = .chats
      } label: {
        Image(systemName: "line.3.horizontal").font(.title3).frame(width: 44, height: 44)
      }.accessibilityLabel("Open chat history")
      Spacer(minLength: 6)
      Button {
        sheet = .model
      } label: {
        VStack(spacing: 3) {
          Text(
            model.workspaces.first(where: { $0.id == model.selectedWorkspace })?.name ?? "OpenWork"
          ).font(.headline).lineLimit(1)
          Text(
            [model.selectedSession?.modelLabel, model.host?.displayName].compactMap { $0 }.joined(
              separator: " · ")
          ).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
        }
      }.accessibilityLabel("Model and chat settings")
      Spacer(minLength: 6)
      Button {
        Task { await model.createChat() }
      } label: {
        Image(systemName: "square.and.pencil").font(.title3).frame(width: 44, height: 44)
      }.disabled(
        model.connection != .ready || model.host?.capabilities.createSession != true
          || model.loading
      ).accessibilityLabel("New chat")
    }.padding(.horizontal, 16).padding(.vertical, 8)
  }
  private var empty: some View {
    VStack(spacing: 20) {
      Spacer()
      BrandMark(size: 52)
      Text("What’s next?").font(.largeTitle.weight(.semibold))
      Text("Pick up a chat, or start something new.\nYour computer takes it from here.").font(.body)
        .foregroundStyle(Theme.muted).multilineTextAlignment(.center)
      Button("Open recent chats") { sheet = .chats }.font(.headline).frame(minHeight: 44)
      Button("Start a new chat") { Task { await model.createChat() } }.buttonStyle(
        PrimaryButtonStyle()
      ).disabled(
        model.host?.capabilities.createSession != true || model.connection != .ready
          || model.loading
      ).padding(.horizontal, 48)
      Spacer()
    }.frame(maxWidth: .infinity)
  }
  private var conversation: some View {
    ScrollViewReader { proxy in
      ZStack(alignment: .bottom) {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            if model.messageCursor != nil {
              Button("Load earlier replies") { Task { await model.earlierMessages() } }.font(
                .caption
              ).frame(maxWidth: .infinity, minHeight: 44)
            }
            ForEach(ConversationPresentation.items(model.messages, compact: compactToolActivity)) { item in
              if item.isActivity {
                CompactActivityView(item: item).id(item.id)
              } else if let message = item.messages.first {
                MessageView(message: message).id(message.id)
              }
            }
            if model.status?.phase == "running"
              && !model.messages.contains(where: { $0.state == "streaming" })
            {
              Label("Working on your computer…", systemImage: "ellipsis").font(.callout)
                .foregroundStyle(Theme.muted).padding(.vertical, 20)
            }
            Color.clear.frame(height: 1).id("bottom")
          }.padding(.horizontal, 24).padding(.bottom, 16)
        }.onScrollGeometryChange(for: Bool.self) { g in
          g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 100
        } action: { _, value in
          nearBottom = value
          if value { newReplies = false }
        }.onAppear {
          nearBottom = true
          newReplies = false
          proxy.scrollTo("bottom", anchor: .bottom)
        }.onChange(of: model.messages) { _, _ in
          if nearBottom {
            if reduceMotion {
              proxy.scrollTo("bottom", anchor: .bottom)
            } else {
              withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
          } else {
            newReplies = true
          }
        }.onChange(of: model.selectedSession?.id) { _, _ in
          nearBottom = true
          newReplies = false
          proxy.scrollTo("bottom", anchor: .bottom)
        }
        if newReplies {
          Button {
            proxy.scrollTo("bottom", anchor: .bottom)
            newReplies = false
          } label: {
            Label("New replies", systemImage: "arrow.down").font(.callout.weight(.semibold))
              .padding(.horizontal, 18).padding(.vertical, 12).background(
                Theme.raised, in: Capsule()
              ).overlay(Capsule().stroke(Theme.line))
          }.padding(.bottom, 12)
        }
      }
    }
  }
}
