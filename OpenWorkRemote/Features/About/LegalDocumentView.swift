import SwiftUI

struct LegalDocumentView: View {
  let document: InformationDocument
  var canonicalURL: URL? = nil
  var isDraft = false
  var body: some View {
    InformationReader(document: document) {
      if let canonicalURL, !isDraft {
        Link(document.id == .terms ? "Read Apple's standard EULA" : "Open the public privacy policy", destination: canonicalURL)
          .accessibilityIdentifier("information-browser-link").padding(.vertical, 12)
      }
    }.navigationTitle(document.id.title).navigationBarTitleDisplayMode(.inline)
  }
}

/// Plain bundled text, never active HTML or remote content.
struct InformationReader<Footer: View>: View {
  let document: InformationDocument
  @ViewBuilder let footer: () -> Footer
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ForEach(Array(document.text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
          if paragraph.hasPrefix("## ") {
            let lines = paragraph.components(separatedBy: "\n")
            VStack(alignment: .leading, spacing: 10) {
              Text(String(lines[0].dropFirst(3))).font(.headline).accessibilityAddTraits(.isHeader)
              Text(lines.dropFirst().joined(separator: "\n")).font(.body).lineSpacing(4)
            }
          } else {
            Text(paragraph).font(.body).lineSpacing(4)
          }
        }
        footer()
      }.textSelection(.enabled).frame(maxWidth: 760, alignment: .leading)
        .padding(24).frame(maxWidth: .infinity)
    }.background(Theme.background).accessibilityIdentifier("information-document-" + document.id.rawValue)
  }
}
