import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@MainActor private final class LaunchFailureSwitch{var fail=true}

@Suite @MainActor struct NativeAppLaunchTests{
  @Test func defaultCompositionPreservesLegacyTextWithoutConnectingItsServer()async throws{
    let directory=FileManager.default.temporaryDirectory.appending(path:"native-launch-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:directory)}
    let disk=try DraftStore(directory:directory),key=DraftKey(hostId:"old",workspaceId:"project",sessionId:"chat")
    var previous=DiskState();previous.conversation.select(key);previous.conversation.setDraft("Keep this earlier text")
    try await disk.save(previous,revision:1)
    let transport=NativeShellTransport(),legacy=StoredPairing(origin:"https://legacy.invalid",token:"synthetic",hostId:"old")
    let app=try AppModel.nativeApp(directory:directory,
      connectionPersistence:OpenCodePersistence(load:{nil},save:{_ in},remove:{}),
      pairingPersistence:PairingPersistence(load:{legacy},save:{_ in},remove:{}),transport:transport)
    await app.start()
    #expect(app.native != nil)
    #expect(app.native?.connection.state == .unpaired)
    #expect(app.nativeMigration?.recoverableText=="Keep this earlier text")
    #expect(await transport.calledPaths().isEmpty)
    #expect(try await disk.load().conversation.draft(for:key)=="Keep this earlier text")
  }
  @Test func storageConstructionFailureHasAnExplicitRetryAndNeverFallsBackToLegacy()throws{
    let directory=FileManager.default.temporaryDirectory.appending(path:"native-launch-retry-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:directory)}
    let failure=LaunchFailureSwitch()
    let launch=NativeAppLaunch(factory:{
      if failure.fail{throw CocoaError(.fileReadNoPermission)}
      return try AppModel.nativeApp(directory:directory,
        connectionPersistence:OpenCodePersistence(load:{nil},save:{_ in},remove:{}),
        pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{}),transport:NativeShellTransport())
    })
    launch.open();#expect(launch.storageUnavailable);#expect(launch.model==nil)
    failure.fail=false;launch.open()
    #expect(!launch.storageUnavailable)
    #expect(launch.model?.native != nil)
    let first=launch.model;launch.open();#expect(launch.model === first)
  }
  @Test func resetReopenFailureCanRetryWithoutRevivingTheRetiredModel()async throws{
    let directory=FileManager.default.temporaryDirectory.appending(path:"native-launch-reset-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:directory)}
    let launch=NativeAppLaunch(factory:{try AppModel.nativeApp(directory:directory,
      connectionPersistence:OpenCodePersistence(load:{nil},save:{_ in},remove:{}),
      pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{}),transport:NativeShellTransport())})
    launch.open();let previous=try #require(launch.model);await previous.start()
    let report=try #require(await previous.resetLocalData());#expect(report.credentialsRemoved && previous.isRetired)
    try FileManager.default.removeItem(at:directory);try Data("Synthetic unavailable directory".utf8).write(to:directory)
    launch.completeReset(report)
    #expect(launch.storageUnavailable && launch.model === previous)
    try FileManager.default.removeItem(at:directory);launch.open()
    let fresh=try #require(launch.model)
    #expect(!launch.storageUnavailable && fresh !== previous && fresh.native != nil)
    #expect(fresh.lastResetReport?.id==report.id)
    await fresh.start();#expect(fresh.native?.connection.state == .unpaired)
  }
}
