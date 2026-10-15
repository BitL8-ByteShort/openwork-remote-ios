import Foundation

/// Required approvals must not depend on optional model/agent catalog reads.
public protocol OpenCodePermissionServing:Sendable {
  func pendingPermissions(target:OpenCodeTarget) async throws -> [OpenCodePermissionRequest]
  func replyPermission(target:OpenCodeTarget,request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision) async throws -> OpenCodePermissionResolution
}
