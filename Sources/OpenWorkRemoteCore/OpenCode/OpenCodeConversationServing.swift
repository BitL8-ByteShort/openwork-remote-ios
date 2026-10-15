import Foundation

public protocol OpenCodeConversationServing:Sendable {
  func session(id:String) async throws -> OpenCodeSession
  func messages(sessionID:String,cursor:String?) async throws -> OpenCodeMessagePage
  func send(target:OpenCodeTarget,input:OpenCodePrompt) async throws -> OpenCodePromptAdmission
  func inbox(target:OpenCodeTarget) async throws -> [OpenCodeInboxItem]
  func activeSessions() async throws -> Set<String>
  func interrupt(target:OpenCodeTarget) async throws -> Bool
  func events() async throws -> AsyncThrowingStream<OpenCodeEvent,any Error>
}
extension OpenCodeClient:OpenCodeConversationServing {}
