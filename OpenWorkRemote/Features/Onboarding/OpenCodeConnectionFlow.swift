import OpenWorkRemoteCore
import SwiftUI

/// Shared by the production native shell and the isolated onboarding UI fixture.
/// Parsing and origin review never start a network request.
struct OpenCodeConnectionFlow:View {
  let coordinator:ConnectionCoordinator
  var migration:ConnectionMigration?
  var onConnected:() -> Void = {}
  var onDataControls:(()->Void)? = nil
  var onAbout:(()->Void)? = nil
  var beginsWithPairing=false
  @Environment(\.scenePhase) private var scenePhase
  @State private var step:Step = .welcome
  @State private var sheet:Sheet?
  @State private var reviewed:OpenCodePairingPayload?
  @State private var selectedOrigin:URL?
  @State private var inputError:String?
  @State private var pairingTask:Task<Void,Never>?
  @State private var copiedDraft=false
  @State private var serverAddress=""
  @State private var serverPassword=""
  @State private var passwordError:String?
  @FocusState private var serverField:ServerField?
  private enum ServerField:Hashable{case address,password}
  private enum Step {case welcome,setup,pair,review,serverPassword,passwordReview}
  private enum Sheet:String,Identifiable {case scan,paste;var id:String{rawValue}}

  var body:some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:24) {
          if coordinator.isBusy { connecting }
          else {
            switch step {
            case .welcome:welcome
            case .setup:setup
            case .pair:pair
            case .review:review
            case .serverPassword:passwordEntry
            case .passwordReview:passwordReview
            }
          }
        }.padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
      }.scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge:.bottom){
          if step == .serverPassword && !coordinator.isBusy{
            VStack(spacing:12){
              Button("Review connection"){reviewServerPassword()}.buttonStyle(PrimaryButtonStyle())
                .disabled(!canReviewPassword).accessibilityIdentifier("native-review-server-password")
              Text("Nothing is sent until you choose Connect.").font(.caption).foregroundStyle(Theme.muted)
            }.padding(24).frame(maxWidth:560).frame(maxWidth:.infinity).background(Theme.background)
          }
        }
        .background(Theme.background).foregroundStyle(Theme.ink)
        .navigationTitle(step == .serverPassword ? "Server password" : step == .passwordReview ? "Review connection" : step == .setup ? "Computer setup" : step == .welcome ? "" : "Pair your computer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          if let onAbout{ToolbarItem(placement:.topBarTrailing){Button(action:onAbout){Label("About & Help",systemImage:"questionmark.circle")}.accessibilityIdentifier("native-about-open")}}
          if let onDataControls{ToolbarItem(placement:.topBarTrailing){Button(action:onDataControls){Label("Data Controls",systemImage:"info.circle")}.accessibilityIdentifier("native-local-data-open")}}
          if step != .welcome && !coordinator.isBusy {
            ToolbarItem(placement:.topBarLeading) {
              Button { back() } label:{Label("Back",systemImage:"chevron.left")}
                .accessibilityIdentifier("native-back")
            }
          }
        }
        .sheet(item:$sheet) { destination in
          switch destination {
          case .paste:NativePairingPaste { parse($0) }
          case .scan:
            NavigationStack {
              QRScannerView { value in sheet=nil;parse(value) }
                .navigationTitle("Scan OpenCode pairing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction){Button("Cancel"){sheet=nil}}}
            }
          }
        }
        .onDisappear {pairingTask?.cancel();serverPassword=""}
        .onAppear{if beginsWithPairing,step == .welcome{step = .pair}}
        .onChange(of:scenePhase){_,phase in
          if phase == .background && (step == .serverPassword || step == .passwordReview){
            pairingTask?.cancel();serverPassword="";serverField=nil;selectedOrigin=nil
            coordinator.cancelPairing();step = .serverPassword
          }
        }
    }
  }
  private var welcome:some View {
    VStack(alignment:.leading,spacing:0) {
      HStack(spacing:12){BrandMark();Text("PocketWork").font(.headline)}.padding(.top,20)
      SetupIllustration().padding(.top,52)
      Text("Your workspace,\nwherever you are.").font(.largeTitle.weight(.semibold))
        .tracking(-1.1).fixedSize(horizontal:false,vertical:true).padding(.top,36)
      Text("Continue your OpenCode v2 chats.\nOn iPhone and iPad.")
        .foregroundStyle(Theme.muted).lineSpacing(5).padding(.top,24)
        .accessibilityIdentifier("native-welcome-copy")
      if migration?.needsNativePairing == true {
        Text("PocketWork now connects to OpenCode. Pair once with its built-in code. Your earlier OpenWork data stays on this device.")
          .font(.callout).foregroundStyle(Theme.muted).padding(.top,20)
        if migration?.recoverableText != nil {
          Button(copiedDraft ? "Earlier draft copied" : "Copy earlier draft text") {
            UIPasteboard.general.string=migration?.recoverableText;copiedDraft=true
          }.frame(minHeight:44).padding(.top,8)
        }
      }
      Button("Get started"){step = .setup}.buttonStyle(PrimaryButtonStyle())
        .padding(.top,44).accessibilityIdentifier("native-get-started")
      Label("Built-in pairing. Your computer runs the work.",systemImage:"checkmark.shield")
        .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth:.infinity).padding(.top,24)
    }
  }
  private var setup:some View {
    VStack(alignment:.leading,spacing:26) {
      Text("First, get your computer ready.").font(.largeTitle.weight(.semibold))
        .tracking(-0.8).fixedSize(horizontal:false,vertical:true)
      setupStep(1,"Keep OpenCode v2 open","Open Settings on your Mac or Linux computer. Keep OpenCode running while you use PocketWork.")
      setupStep(2,"Turn on Remote access","Use OpenCode’s built-in remote connection to reach this computer securely.")
      setupStep(3,"Choose Pair device","Scan its QR code or paste the pairing link into PocketWork.")
      Button("My computer is ready"){step = .pair}.buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("native-computer-ready")
      Text("Pairing codes expire after five minutes and can be used once.")
        .font(.caption).foregroundStyle(Theme.muted)
    }
  }
  private var pair:some View {
    VStack(alignment:.leading,spacing:24) {
      BrandMark()
      Text("Connect your computer.").font(.largeTitle.weight(.semibold)).tracking(-0.8)
      Text("Scan the pairing code shown in OpenCode v2, or paste its pairing link.")
        .foregroundStyle(Theme.muted).lineSpacing(4)
      Image(systemName:"qrcode.viewfinder").font(.system(size:92,weight:.light))
        .foregroundStyle(Theme.accent).frame(maxWidth:.infinity,minHeight:230)
        .background(Theme.surface,in:RoundedRectangle(cornerRadius:28)).accessibilityHidden(true)
      if let inputError {Text(inputError).font(.callout).foregroundStyle(.red).accessibilityIdentifier("native-pairing-error")}
      Button("Scan pairing code"){sheet = .scan}.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native-scan-pairing")
      Button("Paste pairing link"){sheet = .paste}.frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("native-paste-pairing")
      Button("Use server password"){
        serverPassword="";passwordError=nil;coordinator.pairAgain();step = .serverPassword
      }.frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("native-server-password")
      Text("You’ll review the server before connecting.").font(.caption).foregroundStyle(Theme.muted)
    }
  }
  private var canReviewPassword:Bool{
    !serverAddress.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && serverAddress.utf8.count<=4_096 &&
      !serverPassword.isEmpty && serverPassword.utf8.count<=16_384 &&
      !serverPassword.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains)
  }
  private var passwordEntry:some View{
    VStack(alignment:.leading,spacing:24){
      Text("Use your server password.").font(.largeTitle.weight(.semibold)).tracking(-0.8)
      Text("Enter your OpenCode server’s HTTPS address and password.").foregroundStyle(Theme.muted)
      VStack(alignment:.leading,spacing:8){
        Text("Server address").font(.callout).foregroundStyle(Theme.muted)
        TextField("https://computer.example",text:$serverAddress)
          .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
          .textContentType(.URL).submitLabel(.next).focused($serverField,equals:.address)
          .onSubmit{serverField = .password}
          .padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
          .accessibilityLabel("Server address").accessibilityIdentifier("native-server-address")
          .privacySensitive()
      }
      VStack(alignment:.leading,spacing:8){
        Text("Server password").font(.callout).foregroundStyle(Theme.muted)
        SecureField("Server password",text:$serverPassword)
          .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
          .submitLabel(.go).focused($serverField,equals:.password)
          .onSubmit{if canReviewPassword{reviewServerPassword()}}
          .padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
          .accessibilityIdentifier("native-server-password-value").privacySensitive()
      }
      Text("Used only to create this paired connection. PocketWork won’t save this password.")
        .font(.callout).foregroundStyle(Theme.muted)
      if let message=passwordError ?? coordinator.issue.map({passwordIssueText($0)}){
        Text(message).font(.callout).foregroundStyle(.red).accessibilityIdentifier("native-password-error")
      }
    }
  }
  private var passwordReview:some View{
    VStack(alignment:.leading,spacing:24){
      Text("Connect to this OpenCode?").font(.largeTitle.weight(.semibold)).tracking(-0.8)
      Text("Check the address against your computer.").foregroundStyle(Theme.muted)
      if let selectedOrigin{
        Label{Text(verbatim:selectedOrigin.absoluteString).font(.body.monospaced())
          .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("native-password-reviewed-origin")}
          icon:{Image(systemName:"desktopcomputer")}
          .padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:20))
      }
      Text("Your password goes only to this server to create a standard paired connection.").foregroundStyle(Theme.muted)
      Text("Pairing gives PocketWork access to this server’s projects and chats.").font(.callout).foregroundStyle(Theme.muted)
      Button("Connect"){connectUsingServerPassword()}.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native-confirm-server-password")
      Button("Cancel"){
        serverPassword="";selectedOrigin=nil;passwordError=nil;coordinator.cancelPairing();step = .pair
      }.frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("native-cancel-server-password")
    }
  }
  private var review:some View {
    VStack(alignment:.leading,spacing:24) {
      Text("Connect to this OpenCode?").font(.largeTitle.weight(.semibold)).tracking(-0.8)
      Text("Check that this address matches the one shown on your computer.").foregroundStyle(Theme.muted)
      if let selectedOrigin {
        Label {Text(verbatim:selectedOrigin.absoluteString).font(.body.monospaced()).textSelection(.enabled)
          .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("native-reviewed-origin")}
          icon:{Image(systemName:"desktopcomputer")}
          .padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface,in:RoundedRectangle(cornerRadius:20))
      }
      if let reviewed,reviewed.origins.count>1 {
        Menu("Choose another listed address") {
          ForEach(reviewed.origins,id:\.self) {origin in Button(origin.absoluteString){selectedOrigin=origin}}
        }.frame(minHeight:44)
      }
      Text("Pairing gives PocketWork access to this OpenCode server’s projects and chats. Project visibility settings only change what this app shows.")
        .font(.callout).foregroundStyle(Theme.muted).lineSpacing(4)
      if let issue=coordinator.issue {Text(issueText(issue)).font(.callout).foregroundStyle(.red).accessibilityIdentifier("native-pairing-error")}
      if coordinator.issue != nil {
        // Redemption can consume the code even when its response is lost.
        // Discard it before offering another connection attempt.
        Button("Use a fresh pairing code") {
          pairingTask?.cancel();pairingTask=nil;coordinator.pairAgain()
          reviewed=nil;selectedOrigin=nil;inputError=nil;step = .pair
        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native-fresh-pairing-code")
      } else {
        Button("Connect"){connect()}.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native-confirm-connection")
      }
      Button("Cancel"){coordinator.cancelPairing();reviewed=nil;selectedOrigin=nil;step = .pair}
        .frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("native-cancel-review")
    }
  }
  private var connecting:some View {
    VStack(alignment:.leading,spacing:24) {
      Text("Connecting securely.").font(.largeTitle.weight(.semibold))
      ProgressView("Checking your computer…").frame(maxWidth:.infinity,minHeight:160).accessibilityIdentifier("native-connecting")
      Text("OpenCode verifies the pairing code. PocketWork then checks the connection.").foregroundStyle(Theme.muted)
      Button("Cancel pairing") {
        pairingTask?.cancel();serverPassword="";coordinator.cancelPairing();reviewed=nil;selectedOrigin=nil;step = .pair
      }.frame(maxWidth:.infinity,minHeight:44)
    }
  }
  private func setupStep(_ number:Int,_ title:String,_ detail:String)->some View {
    HStack(alignment:.top,spacing:14) {
      Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(Theme.accent)
        .frame(width:30,height:30).background(Theme.accent.opacity(0.1),in:Circle())
      VStack(alignment:.leading,spacing:6){Text(title).font(.headline);Text(detail).font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)}
    }
  }
  private func parse(_ value:String) {
    do {let parsed=try OpenCodePairingPayload.parse(value);reviewed=parsed;selectedOrigin=parsed.origins.first;inputError=nil;step = .review}
    catch {inputError="That isn’t an OpenCode HTTPS pairing code or link. Create a new one in OpenCode and try again.";step = .pair}
  }
  private func connect() {
    guard let reviewed,let selectedOrigin else{return}
    pairingTask?.cancel()
    pairingTask=Task {
      await coordinator.connect(reviewed,origin:selectedOrigin,displayName:selectedOrigin.host ?? "Computer")
      if !Task.isCancelled,coordinator.state == .ready {self.reviewed=nil;self.selectedOrigin=nil;onConnected()}
    }
  }
  private func reviewServerPassword(){
    guard canReviewPassword else{return}
    do{
      let value=serverAddress.trimmingCharacters(in:.whitespacesAndNewlines)
      guard let url=URL(string:value) else{throw RemoteError.invalidPairing}
      let candidate=try OpenCodeConnection(origin:url,displayName:url.host ?? "Computer")
      selectedOrigin=candidate.origin;reviewed=nil;passwordError=nil;serverField=nil
      coordinator.pairAgain();step = .passwordReview
    }catch{passwordError="Enter an HTTPS server address without a pairing path, username, query or fragment."}
  }
  private func connectUsingServerPassword(){
    guard let origin=selectedOrigin,!serverPassword.isEmpty else{return}
    let password=serverPassword;serverPassword="";serverField=nil
    pairingTask?.cancel()
    pairingTask=Task{
      await coordinator.connectUsingServerPassword(origin:origin,password:password,displayName:origin.host ?? "Computer")
      guard !Task.isCancelled else{return}
      if coordinator.state == .ready{selectedOrigin=nil;onConnected()}
      else{passwordError=coordinator.issue.map({passwordIssueText($0)});selectedOrigin=nil;step = .serverPassword}
    }
  }
  private func back() {
    pairingTask?.cancel();coordinator.cancelPairing();inputError=nil;serverPassword="";passwordError=nil;serverField=nil
    switch step {
    case .welcome:break
    case .setup:step = .welcome
    case .pair:step = .setup
    case .review:reviewed=nil;selectedOrigin=nil;step = .pair
    case .serverPassword:selectedOrigin=nil;step = .pair
    case .passwordReview:selectedOrigin=nil;step = .serverPassword
    }
  }
  private func passwordIssueText(_ issue:NativeConnectionIssue)->String {
    switch issue {
    case .freshPairingCodeRequired,.pairingOutcomeUnknown:
      "Connection couldn’t be confirmed. Re-enter the server details to create a fresh paired connection. Your previous connection is retained."
    default:issueText(issue)
    }
  }
  private func issueText(_ issue:NativeConnectionIssue)->String {
    switch issue {
    case .freshPairingCodeRequired:"This pairing code expired or was already used. Create a new code in OpenCode."
    case .pairingOutcomeUnknown:"Pairing couldn’t be confirmed. Create a new code in OpenCode before trying again. Your previous connection is retained."
    case .networkUnavailable:"Your computer couldn’t be reached. Keep OpenCode open and try again."
    case .storageUnavailable:"The connection couldn’t be saved. Unlock this device and try again. Your previous connection is retained."
    case .incompatible:"This OpenCode version hasn’t been qualified for PocketWork yet. Check the supported version before pairing."
    case .serverPasswordRejected:"The server password wasn’t accepted. Check it in OpenCode and enter it again."
    case .passwordConnectionUnconfirmed:"Connection couldn’t be confirmed. Re-enter the server details to try again. Your previous connection is retained."
    }
  }
}

private struct NativePairingPaste:View {
  let onPayload:(String)->Void
  @Environment(\.dismiss) private var dismiss
  @State private var text=""
  var body:some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:20) {
          Text("Paste the pairing link or QR payload copied from OpenCode.").foregroundStyle(Theme.muted)
          TextEditor(text:$text).font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
            .frame(minHeight:200).padding(12).background(Theme.surface,in:RoundedRectangle(cornerRadius:16))
            .privacySensitive().accessibilityIdentifier("native-pairing-payload")
          if text.utf8.count>16_384 {Text("That payload is too large. Copy a fresh pairing link from OpenCode.").font(.callout).foregroundStyle(.red)}
        }.padding(24).frame(maxWidth:560).frame(maxWidth:.infinity)
      }.safeAreaInset(edge:.bottom) {
        Button("Review connection") {let value=text;text="";onPayload(value);dismiss()}
          .buttonStyle(PrimaryButtonStyle()).disabled(text.isEmpty || text.utf8.count>16_384)
          .accessibilityIdentifier("native-review-payload").padding(24).background(Theme.background)
      }.background(Theme.background).navigationTitle("Paste pairing link").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.cancellationAction){Button("Cancel"){text="";dismiss()}}}
        .onDisappear{text=""}
    }
  }
}
