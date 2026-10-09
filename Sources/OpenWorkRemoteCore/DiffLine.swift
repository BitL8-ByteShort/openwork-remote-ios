import Foundation

public struct DiffLine: Sendable, Equatable, Identifiable {
  public enum Kind: Sendable { case header, context, addition, removal }
  public let id: Int
  public let text: String
  public let kind: Kind
  public let shortened: Bool
  // Literal display values only. Never Markdown, HTML, URLs or instructions.
  public static func parse(_ text: String) -> [DiffLine] {
    var rows=text.split(separator:"\n",omittingEmptySubsequences:false)
    if rows.last == "" {rows.removeLast()}
    return rows.prefix(10000).enumerated().map {index,line in
      let kind: Kind
      if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") || line.hasPrefix("diff ") || line.hasPrefix("index ") {kind = .header}
      else if line.hasPrefix("+") {kind = .addition}
      else if line.hasPrefix("-") {kind = .removal}
      else {kind = .context}
      let scalars=line.unicodeScalars,shortened=scalars.count > 2000
      return DiffLine(id:index,text:String(String.UnicodeScalarView(scalars.prefix(2000))),kind:kind,shortened:shortened)
    }
  }
}
