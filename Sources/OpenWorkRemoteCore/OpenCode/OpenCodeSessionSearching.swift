import Foundation
public protocol OpenCodeSessionSearching:Sendable {
  func sessions(projectID:String,cursor:String?,search:String?)async throws->OpenCodeSessionPage
}
extension OpenCodeClient:OpenCodeSessionSearching{}
