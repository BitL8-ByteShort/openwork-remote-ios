import SwiftUI

struct AboutView: View {
  private let information = Result { try ProductInformation.load() }
  var body: some View {
    List {
      Section {
        HStack(spacing: 14) {
          BrandMark(size: 46)
          VStack(alignment: .leading, spacing: 5) {
            Text(ProductInformation.displayName).font(.title2.weight(.semibold))
              .accessibilityIdentifier("about-name")
            Text(ProductInformation.version?.label ?? "Version unavailable")
              .foregroundStyle(Theme.muted).accessibilityIdentifier("about-version")
          }
        }.padding(.vertical, 8)
        Text("An independently maintained companion for OpenWork.").font(.callout)
      }
      switch information {
      case .success(let info):
        Section {
          LabeledContent("Developer", value: info.manifest.publisher)
            .accessibilityElement(children: .combine).accessibilityIdentifier("about-developer")
          NavigationLink { HelpView(information: info) } label: {
            Label("Help", systemImage: "questionmark.circle")
          }.accessibilityIdentifier("about-help")
          Link(destination: info.manifest.supportURL) {
            Label("Get support on GitHub", systemImage: "arrow.up.right.square")
          }.accessibilityIdentifier("about-support")
          Link(destination: info.supportEmailURL) {
            Label("Email support", systemImage: "envelope")
          }.accessibilityIdentifier("about-support-email")
          NavigationLink { DataControlsView() } label: {
            Label("Data on this phone", systemImage: "iphone")
          }.accessibilityIdentifier("about-data-controls")
        } footer: {
          Text("Support issues are public. Leave out pairing codes, tokens, private chats and personal files.")
        }
        Section {
          NavigationLink {
            LegalDocumentView(document: info.document(.privacy), canonicalURL: info.manifest.privacyURL,
              isDraft: !info.manifest.policyApproved)
          } label: { Text("Privacy policy") }.accessibilityIdentifier("about-privacy")
          NavigationLink {
            LegalDocumentView(document: info.document(.terms), canonicalURL: info.manifest.termsURL)
          } label: { Text("Terms of use") }.accessibilityIdentifier("about-terms")
          NavigationLink {
            LegalDocumentView(document: info.document(.sourceLicense))
          } label: { Text("Source license") }.accessibilityIdentifier("about-license")
          NavigationLink {
            LegalDocumentView(document: info.document(.notices))
          } label: { Text("Open-source notices") }.accessibilityIdentifier("about-notices")
        } header: { Text("Legal") } footer: {
          Text("These documents are included in the app and work offline.")
        }
      case .failure:
        Section {
          Text("The bundled information could not be opened. Update the app and try again.")
            .accessibilityIdentifier("information-error")
        }
      }
    }.scrollContentBackground(.hidden).background(Theme.background)
      .navigationTitle("About & Help").navigationBarTitleDisplayMode(.inline)
  }
}
