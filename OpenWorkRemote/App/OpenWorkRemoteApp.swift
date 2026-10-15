import SwiftUI

@main struct OpenWorkRemoteApp: App {
  @State private var launch = NativeAppLaunch()
  @State private var startupAbout=false
  #if DEBUG
  @State private var legacyModel:AppModel?
  #endif
  @Environment(\.scenePhase) private var phase
  @AppStorage("appearance") private var appearance = "system"
  #if DEBUG
    init() {
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-native-startup"){
        let directory=FileManager.default.temporaryDirectory.appending(path:"native-startup-ui-"+UUID().uuidString)
        _launch=State(initialValue:NativeAppLaunch(factory:{
          try AppModel.nativeApp(directory:directory,
            connectionPersistence:OpenCodePersistence(load:{nil},save:{_ in},remove:{}),
            pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{}))
        }))
        return
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-information") || ProcessInfo.processInfo.arguments.contains("-ui-testing-data-controls") {
        let directory = FileManager.default.temporaryDirectory.appending(path: "information-ui-" + UUID().uuidString)
        let fixture = AppModel(pairingPersistence: PairingPersistence(load: { nil }, save: { _ in }, remove: {}),
          draftStore: try? DraftStore(directory: directory))
        _legacyModel = State(initialValue: fixture)
        return
      }
      #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-live-artifacts") {
          _legacyModel = State(initialValue:liveArtifactUITestFixture())
          return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-live-attachments") {
          _legacyModel = State(initialValue:liveAttachmentUITestFixture())
          return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-live-questions") {
          _legacyModel = State(initialValue: liveQuestionUITestFixture())
          return
        }
      #endif
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-chats") {
        _legacyModel = State(initialValue: chatUITestFixture(
          slowMessages: ProcessInfo.processInfo.arguments.contains("-slow-messages"),
          failRename: ProcessInfo.processInfo.arguments.contains("-fail-rename"),
          largeConversation: ProcessInfo.processInfo.arguments.contains("-large-conversation"),
          burstEvents: ProcessInfo.processInfo.arguments.contains("-burst-events"),
          offlineReconnect: ProcessInfo.processInfo.arguments.contains("-offline-reconnect"),
          pendingQuestion: ProcessInfo.processInfo.arguments.contains("-pending-question"),
          staleQuestion: ProcessInfo.processInfo.arguments.contains("-stale-question"),
          unsupportedQuestion: ProcessInfo.processInfo.arguments.contains("-unsupported-question"),
          slowQuestions: ProcessInfo.processInfo.arguments.contains("-slow-questions")))
        return
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-revoked") {
        let fixture = AppModel(pairingPersistence: PairingPersistence(
          load: { nil }, save: { _ in }, remove: {}))
        fixture.connection = .revoked
        _legacyModel = State(initialValue: fixture)
        return
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding"){
        _legacyModel=State(initialValue:AppModel(pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{})))
      }
    }
  #endif
  var body: some Scene {
    WindowGroup {
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-native-app") {
        NativeAppUITestFixture()
      } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-native-forms") {
        NativeFormUITestFixture().tint(Theme.accent)
      } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-native-controls") {
        NativeControlUITestFixture().tint(Theme.accent)
      } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-native-onboarding") {
        NativeOnboardingFixture().tint(Theme.accent)
      } else if let legacyModel {
        legacyRoot(legacyModel)
      } else {
        nativeRoot
      }
      #else
      nativeRoot
      #endif
    }
  }
  private var nativeRoot:some View{
    Group{
      if launch.storageUnavailable{
        VStack(alignment:.leading,spacing:24){
          Text("Saved data is unavailable").font(.largeTitle.weight(.semibold))
          Text("Unlock this device and retry. PocketWork has not discarded your saved connection or drafts.").foregroundStyle(Theme.muted)
          Button("Retry"){launch.open()}.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native-startup-retry")
          Button("About & Help"){startupAbout=true}.frame(minHeight:44).accessibilityIdentifier("native-about-open")
        }.padding(24).frame(maxWidth:560).frame(maxWidth:.infinity,maxHeight:.infinity)
      }else if let model=launch.model{
        NativeRootView().id(ObjectIdentifier(model)).environment(model)
          .task(id:ObjectIdentifier(model)){InteractionMetrics.startSampling();await model.start()}
          .onChange(of:phase){_,value in model.sceneActive(value == .active)}
          .onChange(of:model.resetReplacement?.id){_,_ in if let report=model.resetReplacement{launch.completeReset(report)}}
      }else{ProgressView("Opening PocketWork…").frame(maxWidth:.infinity,maxHeight:.infinity).task{launch.open()}}
    }.background(Theme.background).foregroundStyle(Theme.ink).tint(Theme.accent)
      .preferredColorScheme(appearance == "dark" ? .dark:appearance == "light" ? .light:nil)
      .sheet(isPresented:$startupAbout){NavigationStack{AboutView(allowsDataControls:false).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){startupAbout=false}}}}}
  }
  #if DEBUG
  private func legacyRoot(_ model:AppModel)->some View {
      RootView().id(ObjectIdentifier(model)).environment(model).preferredColorScheme(
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
      ).tint(Theme.accent).task(id: ObjectIdentifier(model)) {
        InteractionMetrics.startSampling()
        await model.start()
      }.onChange(of: phase) { _, p in
        model.sceneActive(p == .active)
      }.onChange(of: model.resetReplacement?.id) { _, _ in
        guard let report = model.resetReplacement else { return }
        do { legacyModel = try model.freshAfterReset(report) }
        catch { model.notice = "Local reset finished, but app storage could not be reopened. Unlock the phone and restart the app." }
      }
  }
  #endif
}
#if DEBUG
private struct NativeOnboardingFixture:View {
  @State private var coordinator=ConnectionCoordinator(
    persistence:OpenCodePersistence(load:{nil},save:{_ in},remove:{}))
  var body:some View {OpenCodeConnectionFlow(coordinator:coordinator)}
}
private struct RootView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    NavigationStack {
      Group {
        if model.isRetired {
          VStack(spacing: 20) {
            ProgressView("Removing local data…")
            if let notice = model.notice { Text(notice).font(.callout) }
          }.padding(24)
        } else if model.connection == .revoked {
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

#endif
