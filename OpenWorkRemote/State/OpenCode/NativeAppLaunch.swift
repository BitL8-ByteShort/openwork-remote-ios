import Foundation
import Observation
import OpenWorkRemoteCore

extension AppModel{
  /// The only production composition. Legacy credentials are read for local
  /// recovery; they are never used to create a network connection here.
  static func nativeApp(directory:URL?=nil,connectionPersistence:OpenCodePersistence = .keychain,
                        pairingPersistence:PairingPersistence = .keychain,
                        transport:any HTTPTransport=SessionTransport(profile:.openCode))throws->AppModel{
    let legacy=try DraftStore(directory:directory)
    let native=try NativeAppCoordinator(directory:legacy.directory,connectionPersistence:connectionPersistence,transport:transport)
    return AppModel(native:native,legacyDraftStore:legacy,pairingPersistence:pairingPersistence,transport:transport)
  }
}

@MainActor @Observable final class NativeAppLaunch{
  private(set) var model:AppModel?
  private(set) var storageUnavailable=false
  @ObservationIgnored private let factory:@MainActor ()throws->AppModel
  @ObservationIgnored private var pendingReset:DataResetReport?
  init(factory:(@MainActor ()throws->AppModel)?=nil){self.factory=factory ?? {try AppModel.nativeApp()}}
  func open(){
    guard model==nil || pendingReset != nil else{return}
    do{
      let fresh:AppModel
      if let report=pendingReset,let model{fresh=try model.freshAfterReset(report)}else{fresh=try factory()}
      // A failed storage open must never become an unpaired legacy instance.
      guard fresh.native != nil else{throw CocoaError(.fileReadCorruptFile)}
      model=fresh;pendingReset=nil;storageUnavailable=false
    }catch{storageUnavailable=true}
  }
  func completeReset(_ report:DataResetReport){pendingReset=report;open()}
}
