import OpenWorkRemoteCore

/// Presentation facts for the shared views; no fabricated bridge Host/capabilities.
extension AppModel {
  var serviceName:String{native == nil ? "OpenWork" : "OpenCode"}
  var computerName:String{native?.connection.connection?.displayName ?? host?.displayName ?? "Your computer"}
  var connectionLabel:String{
    guard let native else{return connection.label}
    switch native.connection.state{
    case .unpaired:return "Not connected"
    case .pairing:return "Pair your computer"
    case .connecting:return "Connecting…"
    case .ready:return "Connected"
    case .offline:return "Computer unavailable"
    case .authenticationRejected:return "Pairing expired or rejected"
    case .incompatible:return "OpenCode update needs qualification"
    case .storageUnavailable:return "Unlock this device to restore the connection"
    }
  }
  var isRunning:Bool{native?.conversation.isActive ?? (status?.phase == "running")}
  var canChooseModel:Bool{native.map{$0.connection.state == .ready && $0.controls.context != nil} ?? (host?.capabilities.modelSettings == true)}
  var canBrowseFiles:Bool{native.map{$0.connection.state == .ready && $0.results.context != nil} ?? (host?.capabilities.artifacts == true)}
  var canCreateChat:Bool{if let native{return native.canCreateChat};return connection == .ready && host?.capabilities.createSession == true && !loading && !uncertainCreation}
  var hasNewerReplies:Bool{native?.navigation.hasNewReplies == true}
  func followLatest(_ following:Bool){native?.followLatest(following)}
  func jumpToLatest(){native?.jumpToLatest()}
}
