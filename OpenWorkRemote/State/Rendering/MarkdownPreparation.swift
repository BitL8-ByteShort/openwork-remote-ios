import Foundation

/// Swift String equality normalizes Unicode. Code updates must retain their raw bytes.
struct MarkdownSource: Equatable, Sendable {
  let text: String
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.text.utf8.elementsEqual(rhs.text.utf8) }
}

struct RenderedMarkdownDocument: Sendable {
  let content: Content
  enum Content: Sendable {
    case rich([Part])
    case plainPages([String])
  }
  enum Part: Sendable {
    case prose([Paragraph])
    case code(text: String, language: String?)
  }
  enum Paragraph: Sendable {
    case heading(String)
    case text(AttributedString)
  }
}

enum MarkdownPreparation {
  private static let formattedBytes = 128 * 1_024
  private static let formattedBlocks = 256
  private static let pageScalars = 4_000

  /// Detached parsing never inherits the caller's UI actor. Cancellation follows
  /// the view task so obsolete streaming versions do not keep preparing replies.
  static func prepare(_ source: String) async throws -> RenderedMarkdownDocument {
    try Task.checkCancellation()
    let worker = Task.detached(priority: .userInitiated) { try render(source) }
    return try await withTaskCancellationHandler {
      let result = try await worker.value
      try Task.checkCancellation()
      return result
    } onCancel: { worker.cancel() }
  }

  private static func render(_ source: String) throws -> RenderedMarkdownDocument {
    try Task.checkCancellation()
    guard source.utf8.count <= formattedBytes else { return try literal(source) }
    let chunks = source.components(separatedBy: "```")
    var parts: [RenderedMarkdownDocument.Part] = []
    var blocks = 0
    for (index, chunk) in chunks.enumerated() {
      try Task.checkCancellation()
      if index % 2 == 1 {
        blocks += 1
        guard blocks <= formattedBlocks, chunk.unicodeScalars.count <= pageScalars else { return try literal(source) }
        let lines = chunk.components(separatedBy: "\n")
        parts.append(.code(text: lines.dropFirst().joined(separator: "\n"),
                           language: lines.first?.isEmpty == false ? lines.first : nil))
      } else if !chunk.isEmpty {
        let paragraphs = chunk.components(separatedBy: "\n\n")
        blocks += paragraphs.count
        guard blocks <= formattedBlocks else { return try literal(source) }
        var prepared: [RenderedMarkdownDocument.Paragraph] = []
        for paragraph in paragraphs {
          try Task.checkCancellation()
          guard paragraph.unicodeScalars.count <= pageScalars else { return try literal(source) }
          if paragraph.hasPrefix("#") {
            prepared.append(.heading(String(paragraph.drop(while: { $0 == "#" || $0 == " " }))))
          } else {
            let attributed = (try? AttributedString(markdown: paragraph,
              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph)
            prepared.append(.text(attributed))
          }
        }
        parts.append(.prose(prepared))
      }
    }
    return RenderedMarkdownDocument(content: .rich(parts))
  }

  private static func literal(_ source: String) throws -> RenderedMarkdownDocument {
    let scalars = source.unicodeScalars
    var start = scalars.startIndex
    var pages: [String] = []
    while start != scalars.endIndex {
      try Task.checkCancellation()
      let end = scalars.index(start, offsetBy: pageScalars, limitedBy: scalars.endIndex) ?? scalars.endIndex
      pages.append(String(scalars[start..<end]))
      start = end
    }
    return RenderedMarkdownDocument(content: .plainPages(pages))
  }
}
