import Foundation

public protocol OpenCodeControlServing:OpenCodePermissionServing {
  func session(id:String) async throws -> OpenCodeSession
  func models(location:OpenCodeLocation) async throws -> [OpenCodeModel]
  func defaultModel(location:OpenCodeLocation) async throws -> OpenCodeModel?
  func agents(location:OpenCodeLocation) async throws -> [OpenCodeAgent]
  func setModel(target:OpenCodeTarget,model:OpenCodeModelRef,expectedModel:OpenCodeModelRef?) async throws -> OpenCodeSession
  func setAgent(target:OpenCodeTarget,agentID:String,expectedAgent:String?) async throws -> OpenCodeSession
  func setSessionRules(target:OpenCodeTarget,rules:[OpenCodePermissionRule],expectedRules:[OpenCodePermissionRule]?) async throws -> OpenCodeSession
  func savedPermissions(target:OpenCodeTarget) async throws -> [OpenCodeSavedPermission]
  func removeSavedPermission(target:OpenCodeTarget,id:String) async throws
}
extension OpenCodeClient:OpenCodeControlServing {}
