import Foundation
import Testing

@testable import OpenWorkRemoteAppState

@Suite struct ProductInformationTests {
  @Test func legalAvailableUnpairedAndOffline() throws {
    let information = try ProductInformation.load()
    for document in InformationDocumentID.allCases {
      #expect(!information.document(document).text.isEmpty)
    }
    #expect(information.manifest.publisher == "Salty Panda LLC")
    #expect(information.manifest.displayName == "PocketWork")
  }

  @Test func helpDoesNotRequireHost() throws {
    let information = try ProductInformation.load()
    #expect(information.document(.help).text.contains("Tailscale"))
    #expect(information.document(.help).text.contains("Remote access"))
    #expect(information.document(.help).text.contains("offline"))
  }

  @Test func supportEmailUsesApprovedAddressWithoutMailHeaders() throws {
    let information = try ProductInformation.load()
    #expect(information.manifest.supportEmail == "support@saltypanda.com")
    #expect(try ProductInformation.supportEmailURL(information.manifest.supportEmail).absoluteString == "mailto:support@saltypanda.com")
    for value in ["", "private@example.com", "support@saltypanda.com?body=private", "support@saltypanda.com\nBcc:private@example.com"] {
      #expect(throws: InformationError.self) { try ProductInformation.supportEmailURL(value) }
    }
  }

  @Test func versionReadsBundle() {
    let version = ProductVersion(info: ["CFBundleShortVersionString": "2.3.4", "CFBundleVersion": "91"])
    #expect(version?.label == "2.3.4 (91)")
    #expect(ProductVersion(info: [:]) == nil)
    #expect(ProductVersion(info: ["CFBundleShortVersionString": "", "CFBundleVersion": "5"]) == nil)
  }

  @Test func policyHasVersionAndDate() throws {
    let information = try ProductInformation.load()
    #expect(!information.manifest.policyVersion.isEmpty)
    #expect(information.document(.privacy).text.contains(information.manifest.effectiveDate))
    #expect(information.document(.privacy).text.contains(information.manifest.policyVersion))
    #expect(information.manifest.privacyURL.absoluteString == "https://bitl8-byteshort.github.io/openwork-remote-ios/privacy/")
  }

  @Test func invalidOrPlaceholderURLFailsReleaseValidation() throws {
    let bad = ["http://example.com", "https://example.com/privacy", "https://localhost/privacy", "https://127.0.0.1/privacy", "https://192.168.1.2/privacy", "https://bitl8-byteshort.github.io@evil.test/privacy", "https://bitl8-byteshort.github.io/openwork-remote-ios/privacy/?token=secret", "javascript:alert(1)"]
    for value in bad {
      #expect(throws: InformationError.self) { try ProductInformation.publicURL(value, kind: .privacy) }
    }
  }

  @Test func unapprovedPolicyFailsIndependentlyOfBundledPublicationStatus() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.copyItem(at: repo.appending(path: "OpenWorkRemote/Resources/Information"), to: directory)
    let manifestURL = directory.appending(path: "manifest.json")
    var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
    manifest["policyApproved"] = false
    try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
    #expect(throws: InformationError.self) { try ProductInformation.load(directory: directory).validateForPublicRelease() }
  }

  @Test func allShippedNoticesPresent() throws {
    let information = try ProductInformation.load()
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let license = try String(contentsOf: repo.appending(path: "LICENSE"), encoding: .utf8)
    #expect(information.document(.sourceLicense).text == license)
    #expect(information.manifest.notices.map(\.id) == ["pocketwork-source"])
    #expect(information.document(.notices).text.contains("No third-party SDK"))
    #expect(information.document(.notices).text.contains("OpenWork"))
  }

  @Test func missingResourceAndMalformedMetadataFailClearly() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(throws: InformationError.self) { try ProductInformation.load(directory: directory) }
    try Data("{}".utf8).write(to: directory.appending(path: "manifest.json"))
    #expect(throws: InformationError.self) { try ProductInformation.load(directory: directory) }
  }
}
