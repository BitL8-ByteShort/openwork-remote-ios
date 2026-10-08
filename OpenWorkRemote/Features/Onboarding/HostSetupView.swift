import SwiftUI

struct HostSetupView: View {
  @Environment(AppModel.self) private var model
  @State private var platform = "macOS"
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        BrandMark()
        Text("Get your computer ready.").font(.largeTitle.weight(.semibold)).tracking(-0.8)
        Text("A quick setup. Then your chats are within reach.").foregroundStyle(Theme.muted)
        Picker("Computer", selection: $platform) {
          Text("macOS").tag("macOS")
          Text("Linux").tag("Linux")
        }.pickerStyle(.segmented)
        VStack(alignment: .leading, spacing: 24) {
          step(1, "Keep OpenWork open", "Use the same computer and workspace you normally work in.")
          step(
            2, "Connect to Tailscale",
            "Connect this iPhone and your computer to the same private network.")
          step(
            3, "Open the bridge setup page",
            "Start OpenWork Remote on your computer, then open its local setup page.")
        }.padding(24).background(Theme.raised, in: RoundedRectangle(cornerRadius: 24))
        DisclosureGroup("Detailed setup") {
          Text(
            "On your \(platform) computer, follow the private repository’s bridge setup guide. The setup page is http://127.0.0.1:9289. Choose Create pairing code."
          ).font(.callout).foregroundStyle(Theme.muted).padding(.top, 8)
        }
      }.padding(24)
    }.safeAreaInset(edge: .bottom) {
      Button("My computer is ready") { model.onboardingStep = 2 }.buttonStyle(
        PrimaryButtonStyle()
      ).accessibilityIdentifier("computer-ready").padding(24).background(Theme.background)
    }.background(Theme.background).foregroundStyle(Theme.ink).navigationTitle("Computer setup")
      .navigationBarTitleDisplayMode(.inline)
  }
  private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(n)").font(.callout.weight(.semibold)).foregroundStyle(Theme.accent).frame(
        width: 30, height: 30
      ).background(Theme.accent.opacity(0.1), in: Circle())
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        Text(detail).font(.callout).foregroundStyle(Theme.muted).fixedSize(
          horizontal: false, vertical: true)
      }
    }
  }
}
