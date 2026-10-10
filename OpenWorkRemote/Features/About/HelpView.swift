import SwiftUI

struct HelpView: View {
  let information: ProductInformation
  var body: some View {
    InformationReader(document: information.document(.help)) {
      Link("Email support", destination: information.supportEmailURL)
        .accessibilityIdentifier("help-support-email").padding(.vertical, 12)
      Link("Get support on GitHub", destination: information.manifest.supportURL)
        .accessibilityIdentifier("help-support").padding(.vertical, 12)
    }.navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
  }
}
