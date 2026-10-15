import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite struct LegacyLocalRecoveryTests {
  @Test func malformedSkillRecoveryCannotBeSilentlyRewrittenByClearDrafts() async throws {
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let bytes=Data(#"{"drafts":[{"hostId":"old","workspaceId":"project","catalogRevision":"invalid","name":"Draft","content":"Keep until inspected"}],"intents":[]}"#.utf8)
    let url=root.appending(path:"skills.json");try bytes.write(to:url)
    let recovery=LegacyLocalRecovery(directory:root)
    #expect(!(await recovery.clearUnsentDrafts()))
    #expect(try Data(contentsOf:url)==bytes)
  }
  @Test func retiredRecoveryCannotRecreateRemovedFilesAndKeepsUnknownRootData() async throws {
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let known=["questions.json","skills.json","chat-actions.json","groups.json","workspace-defaults.json","attachments.json"]
    for name in known{try Data("Synthetic obsolete metadata".utf8).write(to:root.appending(path:name))}
    let unknown=root.appending(path:"keep-unknown.txt");try Data("Keep".utf8).write(to:unknown)
    let recovery=LegacyLocalRecovery(directory:root)
    #expect(await recovery.removeAll().isEmpty)
    #expect(!(await recovery.clearUnsentDrafts()))
    for name in known{#expect(!FileManager.default.fileExists(atPath:root.appending(path:name).path))}
    #expect(try String(contentsOf:unknown,encoding:.utf8)=="Keep")
  }
}
