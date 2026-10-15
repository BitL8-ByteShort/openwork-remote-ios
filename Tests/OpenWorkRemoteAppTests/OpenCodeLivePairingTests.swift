import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

/// Opt-in integration only. A fresh, owner-controlled native QR payload is read
/// from a private file; no pairing codes, origins or credentials enter diagnostics.
@Suite @MainActor struct OpenCodeLivePairingTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_PAIRING_FIXTURE"] != nil))
  func nativeHTTPSPairingAndCredentialReload() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_PAIRING_FIXTURE"])
    let bytes = try Data(contentsOf:URL(fileURLWithPath:path))
    #expect(bytes.count <= 16_384)
    let payload = try OpenCodePairingPayload.parse(try #require(String(data:bytes,encoding:.utf8)))
    let origin = try #require(payload.origins.first)
    let saved = NativeSavedConnection()
    let connection = ConnectionCoordinator(persistence:saved.persistence)
    await connection.connect(payload,origin:origin,displayName:"Disposable native qualification")
    #expect(connection.state == .ready)
    let info = try await #require(connection.client).info()
    #expect(info.version == "2.0.29")
    let restored = ConnectionCoordinator(persistence:saved.persistence)
    await restored.start()
    #expect(restored.state == .ready)
    #expect(restored.connection?.id == connection.connection?.id)
    await #expect(throws:RemoteError.unauthorized) {
      _ = try await OpenCodePairingClient().redeem(payload,origin:origin)
    }
    restored.forgetLocalConnection()
    #expect(saved.value == nil)
  }
}
