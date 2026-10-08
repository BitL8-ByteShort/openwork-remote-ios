import SwiftUI

struct MarkdownView: View {
  let text: String
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
        if part.code {
          CodeBlockView(text: part.text, language: part.language)
        } else {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(part.text.components(separatedBy: "\n\n").enumerated()), id: \.offset) {
              _, paragraph in
              if paragraph.hasPrefix("#") {
                Text(paragraph.drop(while: { $0 == "#" || $0 == " " })).font(
                  .title3.weight(.semibold))
              } else {
                Text(
                  (try? AttributedString(
                    markdown: paragraph,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(paragraph)
                ).font(.body).lineSpacing(5).textSelection(.enabled)
              }
            }
          }
        }
      }
    }
  }
  private var parts: [MarkdownPart] {
    var result: [MarkdownPart] = []
    let chunks = text.components(separatedBy: "```")
    for (i, chunk) in chunks.enumerated() {
      if i % 2 == 0 {
        if !chunk.isEmpty { result.append(MarkdownPart(text: chunk, language: nil, code: false)) }
      } else {
        let lines = chunk.components(separatedBy: "\n")
        result.append(
          MarkdownPart(
            text: lines.dropFirst().joined(separator: "\n"),
            language: lines.first?.isEmpty == false ? lines.first : nil, code: true))
      }
    }
    return result
  }
}
private struct MarkdownPart {
  let text: String
  let language: String?
  let code: Bool
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
          Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(
            .caption)
        }.frame(minHeight: 44)
      }.padding(.horizontal, 14).foregroundStyle(Theme.muted)
      ScrollView(.horizontal) {
        Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(16)
          .fixedSize(horizontal: true, vertical: false)
      }.frame(maxHeight: 360)
    }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 18)).overlay(
      RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
  }
}
