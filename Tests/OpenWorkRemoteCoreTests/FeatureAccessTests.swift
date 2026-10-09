import Foundation
import Testing
@testable import OpenWorkRemoteCore

private func featureFixture(_ file: String) throws -> Data {
  let folder = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
  let wrapper = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: file))) as? [String: Any])
  return try JSONSerialization.data(withJSONObject: wrapper["value"]!)
}

@Test func oldHostDisablesNewFeaturesAndRetainsChatCapabilities() throws {
  for name in ["host-linux.json", "host-macos.json"] {
    let host = try JSONDecoder().decode(Host.self, from: featureFixture(name))
    let access = FeatureAccess(capabilities: host.capabilities, grants: .none)
    #expect(host.capabilities.readSessions)
    #expect(host.capabilities.readMessages)
    for feature in RemoteFeature.allCases { #expect(access.availability(for: feature) == .unsupported) }
  }
}

@Test func oldDeviceDoesNotGainPrivileges() throws {
  let device = try JSONDecoder().decode(DeviceAccess.self, from: Data(#"{"allWorkspaces":true,"workspaceIds":[]}"#.utf8))
  #expect(device.features == .none)
  #expect(device.allWorkspaces)
  let partial = try JSONDecoder().decode(DeviceAccess.self, from: Data(#"{"allWorkspaces":false,"workspaceIds":["owned"],"features":{"fileTransfer":true}}"#.utf8))
  #expect(partial.features.fileTransfer)
  #expect(!partial.features.workspaceAdministration)
  #expect(!partial.features.automationManagement)
}

@Test func advertisedFeaturesRequireTheirSpecificHostGrant() throws {
  let host = try JSONDecoder().decode(Host.self, from: featureFixture("host-feature-fixture.json"))
  let denied = FeatureAccess(capabilities: host.capabilities, grants: .none)
  for feature in [RemoteFeature.questions, .sessionGroups, .forkSession, .deleteSession, .searchSessions] {
    #expect(denied.availability(for: feature) == .available)
  }
  for feature in [RemoteFeature.attachments, .artifacts, .changes] {
    #expect(denied.availability(for: feature) == .needsHostGrant(.fileTransfer))
  }
  for feature in [RemoteFeature.workspaceDefaults, .skillsRead, .skillsWrite] {
    #expect(denied.availability(for: feature) == .needsHostGrant(.workspaceAdministration))
  }
  for feature in [RemoteFeature.automationsRead, .automationsWrite] {
    #expect(denied.availability(for: feature) == .needsHostGrant(.automationManagement))
  }
  let granted = FeatureAccess(capabilities: host.capabilities,
    grants: DeviceFeatureGrants(fileTransfer: true, workspaceAdministration: true, automationManagement: true))
  for feature in RemoteFeature.allCases { #expect(granted.availability(for: feature) == .available) }
}

@Test func malformedFeatureFlagsAndGrantsRejectInsteadOfExpandingAccess() throws {
  let source = try #require(JSONSerialization.jsonObject(with: featureFixture("host-feature-fixture.json")) as? [String: Any])
  for feature in RemoteFeature.allCases {
    var malformed = source
    var capabilities = try #require(source["capabilities"] as? [String: Any])
    capabilities[feature.rawValue] = "true"
    malformed["capabilities"] = capabilities
    let data = try JSONSerialization.data(withJSONObject: malformed)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(Host.self, from: data) }
  }
  for key in ["fileTransfer", "workspaceAdministration", "automationManagement"] {
    let data = try JSONSerialization.data(withJSONObject: ["allWorkspaces":false,"workspaceIds":["owned"],"features":[key:"true"]])
    #expect(throws: (any Error).self) { try JSONDecoder().decode(DeviceAccess.self, from: data) }
  }
}
