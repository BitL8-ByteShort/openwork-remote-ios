import SwiftUI

@main struct OpenWorkRemoteApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var phase
  @AppStorage("appearance") private var appearance = "system"
  var body: some Scene {
    WindowGroup {
      RootView().environment(model).preferredColorScheme(
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
      ).tint(Theme.accent).task { await model.start() }.onChange(of: phase) { _, p in
        model.sceneActive(p == .active)
      }
    }
  }
}
private struct RootView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    NavigationStack {
      Group {
        if model.hasPairing || model.host != nil {
          if model.onboardingStep == 4 { WorkspacePicker() } else { ChatView() }
        } else {
          switch model.onboardingStep {
          case 1: HostSetupView()
          case 2: PairingView()
          default: WelcomeView()
          }
        }
      }.toolbar {
        if model.host == nil && model.onboardingStep > 0 {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              model.cancelPairing()
              model.onboardingStep -= 1
            } label: {
              Label("Back", systemImage: "chevron.left")
            }
          }
        }
      }
    }.foregroundStyle(Theme.ink)
  }
}
