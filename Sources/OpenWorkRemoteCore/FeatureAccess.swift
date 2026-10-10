import Foundation

public struct DeviceFeatureGrants: Codable, Sendable, Equatable {
  public let fileTransfer: Bool
  public let workspaceAdministration: Bool
  public let automationManagement: Bool
  public static let none = DeviceFeatureGrants(fileTransfer: false, workspaceAdministration: false, automationManagement: false)
  public init(fileTransfer: Bool, workspaceAdministration: Bool, automationManagement: Bool) {
    self.fileTransfer = fileTransfer
    self.workspaceAdministration = workspaceAdministration
    self.automationManagement = automationManagement
  }
  enum CodingKeys: String, CodingKey { case fileTransfer, workspaceAdministration, automationManagement }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    fileTransfer = try c.decodeIfPresent(Bool.self, forKey: .fileTransfer) ?? false
    workspaceAdministration = try c.decodeIfPresent(Bool.self, forKey: .workspaceAdministration) ?? false
    automationManagement = try c.decodeIfPresent(Bool.self, forKey: .automationManagement) ?? false
  }
}

public enum DeviceFeatureGrant: Sendable, Equatable {
  case fileTransfer, workspaceAdministration, automationManagement
}
public enum RemoteFeature: String, CaseIterable, Sendable {
  case questions, attachments, artifacts, changes, sessionGroups, forkSession, deleteSession
  case searchSessions, workspaceDefaults, skillsRead, skillsWrite, automationsRead, automationsWrite
}
public enum FeatureAvailability: Sendable, Equatable {
  case available, unsupported
  case needsHostGrant(DeviceFeatureGrant)
}

/// Presentation for a selected workspace. The host still authorizes every
/// workspace/session operation; a capability flag is never an access credential.
public struct FeatureAccess: Sendable {
  private let capabilities: Capabilities
  private let grants: DeviceFeatureGrants
  public init(capabilities: Capabilities, grants: DeviceFeatureGrants) {
    self.capabilities = capabilities
    self.grants = grants
  }
  public func availability(for feature: RemoteFeature) -> FeatureAvailability {
    let supported: Bool?
    let required: DeviceFeatureGrant?
    switch feature {
    case .questions: supported = capabilities.questions; required = nil
    case .attachments: supported = capabilities.attachments; required = .fileTransfer
    case .artifacts: supported = capabilities.artifacts; required = .fileTransfer
    case .changes: supported = capabilities.changes; required = .fileTransfer
    case .sessionGroups: supported = capabilities.sessionGroups; required = nil
    case .forkSession: supported = capabilities.forkSession; required = nil
    case .deleteSession: supported = capabilities.deleteSession; required = nil
    case .searchSessions: supported = capabilities.searchSessions; required = nil
    case .workspaceDefaults: supported = capabilities.workspaceDefaults; required = .workspaceAdministration
    case .skillsRead: supported = capabilities.skillsRead; required = .workspaceAdministration
    case .skillsWrite: supported = capabilities.skillsWrite; required = .workspaceAdministration
    case .automationsRead: supported = capabilities.automationsRead; required = .automationManagement
    case .automationsWrite: supported = capabilities.automationsWrite; required = .automationManagement
    }
    guard supported == true else { return .unsupported }
    guard let required else { return .available }
    let granted: Bool
    switch required {
    case .fileTransfer: granted = grants.fileTransfer
    case .workspaceAdministration: granted = grants.workspaceAdministration
    case .automationManagement: granted = grants.automationManagement
    }
    return granted ? .available : .needsHostGrant(required)
  }
}
