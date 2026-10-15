import SwiftUI

/// Native production root. Legacy network onboarding is a DEBUG fixture only.
struct NativeRootView:View{
  @Environment(AppModel.self) private var model
  @State private var dataControls=false
  @State private var about=false
  private struct ConnectionObservation:Equatable{
    let state:NativeConnectionState
    let client:ObjectIdentifier?
  }
  var body:some View{
    Group{
      if let native=model.native{
        Group{
          if model.isRetired{ProgressView("Removing local data…").padding(24)}
          else if native.startupState == .loading{ProgressView("Opening PocketWork…").padding(24)}
          else if native.startupState == .storageUnavailable{
            problem("Saved data is unavailable","Unlock this device and retry. Your saved connection has not been treated as a new installation.",retry:{Task{await model.start()}})
          }else if let report=model.lastResetReport,!report.credentialsRemoved{
            problem("Local reset is incomplete",report.summary,retry:{Task{_ = await model.resetLocalData()}},button:"Retry reset")
          }else{
            switch native.connection.state{
            case .unpaired,.pairing:
              OpenCodeConnectionFlow(coordinator:native.connection,migration:model.nativeMigration,
                onConnected:{Task{await native.connectionChanged()}},onDataControls:{dataControls=true},onAbout:{about=true},
                beginsWithPairing:native.connection.state == .pairing)
            case .ready,.connecting,.offline:
              NavigationStack{ChatView()}
            case .authenticationRejected:
              problem("Pair your computer again","OpenCode rejected the saved credential. Create a fresh pairing code on your computer. Saved drafts stay on this device.",retry:{native.connection.pairAgain()},button:"Pair again")
            case .incompatible:
              problem("This OpenCode version needs testing","PocketWork has not qualified this server version for writes. Keep your drafts and check the supported version before continuing.",retry:{Task{await native.reconnect()}})
            case .storageUnavailable:
              problem("Saved connection is unavailable","Unlock this device and retry the saved connection. Local files remain available for recovery or reset.",retry:{Task{await native.connection.start();await native.connectionChanged()}})
            }
          }
        }.task(id:ConnectionObservation(state:native.connection.state,client:native.connection.client.map(ObjectIdentifier.init))){
          if native.connection.state == .ready{await native.connectionChanged()}
        }
      }else{Text("PocketWork’s native connection could not be opened.").padding(24)}
    }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Theme.background).foregroundStyle(Theme.ink)
      .sheet(isPresented:$dataControls){
        NavigationStack{DataControlsView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dataControls=false}.frame(minHeight:44)}}}
      }
      .sheet(isPresented:$about){NavigationStack{AboutView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){about=false}.frame(minHeight:44).accessibilityIdentifier("native-about-done")}}}}
  }
  private func problem(_ title:String,_ message:String,retry:@escaping()->Void,button:String="Retry")->some View{
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:24){
          BrandMark()
          Text(title).font(.largeTitle.weight(.semibold))
          Text(message).foregroundStyle(Theme.muted)
          Button(button,action:retry).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native-recovery-retry")
          Button("Data Controls"){dataControls=true}.frame(minHeight:44).accessibilityIdentifier("native-local-data-open")
        }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
      }.background(Theme.background).navigationTitle("PocketWork").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.topBarTrailing){Button("About & Help"){about=true}.accessibilityIdentifier("native-about-open")}}
    }
  }
}
