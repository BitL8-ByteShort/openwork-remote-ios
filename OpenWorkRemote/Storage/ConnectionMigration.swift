import Foundation
import OpenWorkRemoteCore

struct ConnectionMigration: CustomStringConvertible, CustomDebugStringConvertible {
  let needsNativePairing: Bool
  let recoverableText: String?
  var description: String { "PocketWork connection migration (private data redacted)" }
  var debugDescription: String { description }
  init(legacy: StoredPairing?, disk: DiskState) {
    needsNativePairing = legacy != nil
    // Recovery exposes text only, for an explicit copy action. It does not move
    // pending operations, skills or attachments to a different backend/target.
    let text = disk.conversation.selected.flatMap { disk.conversation.draft(for: $0) }
    recoverableText = text?.isEmpty == false ? text : nil
  }
  static func draftKey(connection:OpenCodeConnection,projectID:String,sessionID:String) -> DraftKey {
    DraftKey(hostId:"opencode-v2:" + connection.id.rawValue.uuidString.lowercased(),
      workspaceId:projectID,sessionId:sessionID)
  }
}
