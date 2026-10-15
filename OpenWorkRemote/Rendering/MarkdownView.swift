import SwiftUI

private struct MarkdownDidPrepareKey: EnvironmentKey {
  static let defaultValue: @MainActor @Sendable () -> Void = {}
}
extension EnvironmentValues {
  var markdownDidPrepare: @MainActor @Sendable () -> Void {
    get { self[MarkdownDidPrepareKey.self] }
    set { self[MarkdownDidPrepareKey.self] = newValue }
  }
}

struct MarkdownView: View {
  let text: String
  @Environment(\.markdownDidPrepare) private var didPrepare
  @State private var document: RenderedMarkdownDocument?
  @State private var readerPresented = false
  var body: some View {
    Group {
      if let document {
        switch document.content {
        case .rich(let parts):
          VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
              switch part {
              case .code(let text, let language): CodeBlockView(text: text, language: language)
              case .prose(let paragraphs):
                VStack(alignment: .leading, spacing: 10) {
                  ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    switch paragraph {
                    case .heading(let heading): Text(heading).font(.title3.weight(.semibold))
                    case .text(let attributed):
                      Text(attributed).font(.body).lineSpacing(5).textSelection(.enabled)
                    }
                  }
                }
              }
            }
          }
        case .plainPages(let pages):
          Button { readerPresented = true } label: {
            Label { Text("Read reply").font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true) }
              icon: { Image(systemName: "doc.text").font(.system(size: 22)) }
              .frame(minHeight: 44).padding(16)
          }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("Read long reply").accessibilityValue("Plain text, \(pages.count) pages")
            .accessibilityIdentifier("long-reply-open")
            .sheet(isPresented: $readerPresented) { LongReplyReader(pages: pages, source: text) }
        }
      } else {
        ProgressView("Preparing reply…").font(.caption)
      }
    }.task(id: MarkdownSource(text: text)) {
      do {
        let prepared = try await MarkdownPreparation.prepare(text)
        try Task.checkCancellation()
        document = prepared
        didPrepare()
      } catch is CancellationError { /* Superseded text or a departed screen. */ }
      catch { /* Preparation only throws cancellation; keep the previous render. */ }
    }
  }
}

/// A bounded page and fixed controls remain usable even when the chat has only
/// a small viewport at accessibility sizes. No omitted or truncated text.
private struct LongReplyReader: View {
  let pages: [String]
  let source: String
  @Environment(\.dismiss) private var dismiss
  @State private var page = 0
  @State private var copied = false
  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading) {
            Color.clear.frame(height: 1).id("page-top")
            if !pages.isEmpty {
              Text(pages[min(page, pages.count - 1)]).font(.body).lineSpacing(5)
                .textSelection(.enabled).accessibilityIdentifier("long-reply-page")
            }
          }.frame(maxWidth: Theme.contentMaxWidth, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.onChange(of: page) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
      }.background(Theme.background).foregroundStyle(Theme.ink)
        .navigationTitle("Long reply").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("long-reply-done")
          }
          ToolbarItem(placement: .topBarLeading) {
            Button {
              UIPasteboard.general.string = source; copied = true
            } label: {
              Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 20)).frame(width: 44, height: 44)
            }.accessibilityLabel(copied ? "Reply copied" : "Copy entire reply")
          }
        }.safeAreaInset(edge: .bottom) {
          HStack(spacing: 12) {
            Button { page = max(0, page - 1) } label: {
              Image(systemName: "chevron.left").font(.system(size: 22)).frame(width: 44, height: 44)
            }.disabled(page == 0).accessibilityLabel("Previous page").accessibilityIdentifier("long-reply-previous")
            Spacer(minLength: 0)
            Text("Page \(min(page + 1, pages.count)) of \(pages.count)").font(.caption)
              .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("long-reply-position")
            Spacer(minLength: 0)
            Button { page = min(pages.count - 1, page + 1) } label: {
              Image(systemName: "chevron.right").font(.system(size: 22)).frame(width: 44, height: 44)
            }.disabled(page >= pages.count - 1).accessibilityLabel("Next page").accessibilityIdentifier("long-reply-next")
          }.padding(.horizontal, 20).padding(.vertical, 8).background(Theme.surface)
        }.onChange(of: pages.count) { _, count in page = min(page, max(0, count - 1)) }
    }
  }
}

struct CodeBlockView: View {
  let text: String
  let language: String?
  @State private var copied = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(language ?? "Code").font(.caption.weight(.medium))
        Spacer()
        Button {
          UIPasteboard.general.string = text
          copied = true
        } label: {
          Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
        }.frame(minHeight: 44)
      }.padding(.horizontal, 14).foregroundStyle(Theme.muted)
      ScrollView([.horizontal, .vertical]) {
        Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(16)
          .fixedSize(horizontal: true, vertical: true).accessibilityIdentifier("code-block-content")
      }.frame(maxHeight: 360).accessibilityIdentifier("code-block-scroll")
    }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 18)).overlay(
      RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
  }
}
