import SwiftUI

struct WelcomeView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
          BrandMark()
          Text(ProductInformation.displayName).font(.headline)
        }.padding(.top, 20)
        if let report = model.lastResetReport {
          Text(report.summary).font(.callout).foregroundStyle(Theme.muted)
            .padding(.top, 24).accessibilityIdentifier("welcome-reset-report")
        }
        SetupIllustration().padding(.top, 58)
        Text("Your workspace,\nwherever you are.").font(.largeTitle.weight(.semibold)).tracking(
          -1.1
        ).fixedSize(horizontal: false, vertical: true).padding(.top, 38)
        Text("Continue your OpenWork chats from your phone. Your computer does the work.").font(
          .body
        ).foregroundStyle(Theme.muted).lineSpacing(5).padding(.top, 24)
        Button("Get started") { model.onboardingStep = 1 }.buttonStyle(PrimaryButtonStyle())
          .padding(.top, 44).accessibilityIdentifier("get-started")
        HStack(spacing: 6) {
          Image(systemName: "checkmark.shield")
          Text("A private connection to your computer").font(.caption)
        }.foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 24)
        NavigationLink { AboutView() } label: {
          Label("About & Help", systemImage: "questionmark.circle")
            .frame(maxWidth: .infinity).frame(minHeight: 44)
        }.padding(.top, 12).accessibilityIdentifier("welcome-about")
      }.padding(.horizontal, 24).padding(.bottom, 24)
    }.background(Theme.background).foregroundStyle(Theme.ink)
  }
}
