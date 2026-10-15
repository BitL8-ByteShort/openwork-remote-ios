import Foundation

public protocol OpenCodeControlServing:Sendable {
  func session(id:String) async throws -> OpenCodeSession
  func models(location:OpenCodeLocation) async throws -> [OpenCodeModel]
  func defaultModel(location:OpenCodeLocation) async throws -> OpenCodeModel?
  func agents(location:OpenCodeLocation) async throws -> [OpenCodeAgent]
  func setModel(target:OpenCodeTarget,model:OpenCodeModelRef,expectedModel:OpenCodeModelRef?) async throws -> OpenCodeSession
  func setAgent(target:OpenCodeTarget,agentID:String,expectedAgent:String?) async throws -> OpenCodeSession
  func setSessionRules(target:OpenCodeTarget,rules:[OpenCodePermissionRule],expectedRules:[OpenCodePermissionRule]?) async throws -> OpenCodeSession
  func pendingPermissions(target:OpenCodeTarget) async throws -> [OpenCodePermissionRequest]
  func replyPermission(target:OpenCodeTarget,request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision) async throws -> OpenCodePermissionResolution
  func savedPermissions(target:OpenCodeTarget) async throws -> [OpenCodeSavedPermission]
  func removeSavedPermission(target:OpenCodeTarget,id:String) async throws
}
extension OpenCodeClient:OpenCodeControlServing {}
