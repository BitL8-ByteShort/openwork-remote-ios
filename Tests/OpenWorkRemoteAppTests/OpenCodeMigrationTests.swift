import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct OpenCodeMigrationTests {
  @Test func exactLegacyPairingAndDiskRemainRecoverableWithoutCredentialReuse() throws {
    let original = Data(#"{"origin":"https://old.example","token":"legacy-secret","hostId":"old-host"}"#.utf8)
    let legacy = try JSONDecoder().decode(StoredPairing.self,from:original)
    var disk = DiskState()
    let old = DraftKey(hostId:legacy.hostId,workspaceId:"project",sessionId:"chat")
    disk.conversation.select(old); disk.conversation.setDraft("Keep this draft")
    let pending = try disk.conversation.beginSend(ready:true)
    disk.conversation.applyReceipt(pending,accepted:false)
    let bytes = try JSONEncoder().encode(disk)
    let restored = try JSONDecoder().decode(DiskState.self,from:bytes)
    let migration = ConnectionMigration(legacy:legacy,disk:restored)
    #expect(migration.needsNativePairing)
    #expect(migration.recoverableText == "Keep this draft")
    #expect(restored.conversation.pendingRequestId(for:old) == pending.requestId)
    #expect(restored.conversation.uncertain.contains(old))
    #expect(legacy.token == "legacy-secret")
    #expect(!String(describing:migration).contains("legacy-secret"))
    #expect(!String(reflecting:migration).contains("legacy-secret"))
  }
  @Test func nativeDraftIdentityDoesNotCollideWithLegacyOrAnotherComputer() throws {
    let one = try nativeStored(), other = try nativeStored()
    let a = ConnectionMigration.draftKey(connection:one.connection,projectID:"project",sessionID:"chat")
    let b = ConnectionMigration.draftKey(connection:other.connection,projectID:"project",sessionID:"chat")
    #expect(a != b)
    #expect(a.hostId.hasPrefix("opencode-v2:"))
    #expect(a != DraftKey(hostId:"old-host",workspaceId:"project",sessionId:"chat"))
    #expect(ConnectionMigration(legacy:nil,disk:DiskState()).recoverableText == nil)
  }
  @Test func aSingleNewEnvelopeSurvivesRestartWithoutTouchingLegacy() async throws {
    let legacy = StoredPairing(origin:"https://one.example",token:"legacy-secret",hostId:"old-host")
    let saved = NativeSavedConnection(), transport = NativeConnectionTransport()
    let initial = ConnectionCoordinator(persistence:saved.persistence,transport:transport)
    let payload = try OpenCodePairingPayload.parse("https://one.example/auth/connect/synthetic")
    await initial.connect(payload,origin:payload.origins[0],displayName:"Computer")
    let bytes = try JSONEncoder().encode(try #require(saved.value))
    let decoded = try JSONDecoder().decode(StoredOpenCodeConnection.self,from:bytes)
    #expect(decoded.connection.backend == .openCodeV2)
    #expect(!String(reflecting:decoded).contains("native-new-token"))
    let reloaded = NativeSavedConnection(decoded)
    let next = ConnectionCoordinator(persistence:reloaded.persistence,transport:transport)
    await next.start()
    #expect(next.state == .ready)
    #expect(next.connection?.id == initial.connection?.id)
    #expect(legacy.token == "legacy-secret")
    #expect(OpenCodeCredentialStore.service != "com.saltypanda.openworkremote.pairing")
  }
}
