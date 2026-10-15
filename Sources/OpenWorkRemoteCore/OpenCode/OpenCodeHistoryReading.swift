import Foundation

public protocol OpenCodeHistoryReading: Sendable {
  func projects() async throws -> [OpenCodeProject]
  func sessions(projectID:String,cursor:String?,search:String?) async throws -> OpenCodeSessionPage
  func session(id:String) async throws -> OpenCodeSession
  func messages(sessionID:String,cursor:String?) async throws -> OpenCodeMessagePage
}
extension OpenCodeClient: OpenCodeHistoryReading {}
