import SwiftUI

@main struct OpenWorkRemoteApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var phase
  @AppStorage("appearance") private var appearance = "system"
  #if DEBUG
    init() {
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-revoked") {
        let fixture = AppModel(pairingPersistence: PairingPersistence(
          load: { nil }, save: { _ in }, remove: {}))
        fixture.connection = .revoked
        _model = State(initialValue: fixture)
      }
    }
  #endif
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
        if model.connection == .revoked {
          RevokedConnectionView()
        } else if model.hasPairing || model.host != nil {
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
