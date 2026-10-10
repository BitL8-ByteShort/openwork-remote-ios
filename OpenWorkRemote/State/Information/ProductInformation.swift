import Foundation

enum InformationError: Error { case missingResource, invalidMetadata, invalidURL, policyNeedsApproval }

enum InformationDocumentID: String, CaseIterable, Codable, Sendable {
  case help, privacy, terms, sourceLicense, notices
  var title: String {
    switch self {
    case .help: "Help"
    case .privacy: "Privacy policy"
    case .terms: "Terms of use"
    case .sourceLicense: "Source license"
    case .notices: "Open-source notices"
    }
  }
  var filename: String { rawValue + ".txt" }
}

struct InformationDocument: Sendable {
  let id: InformationDocumentID
  let text: String
}

struct ProductVersion: Equatable, Sendable {
  let version: String
  let build: String
  var label: String { "\(version) (\(build))" }
  init?(info: [String: Any]) {
    guard let version = info["CFBundleShortVersionString"] as? String,
      let build = info["CFBundleVersion"] as? String,
      !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    self.version = version
    self.build = build
  }
}

/// Local text and fixed, explicit browser destinations. No host or network dependency.
struct ProductInformation: Sendable {
  struct Notice: Decodable, Sendable { let id: String; let name: String; let license: String }
  struct Manifest: Decodable, Sendable {
    let schemaVersion: Int
    let displayName: String
    let publisher: String
    let policyVersion: String
    let effectiveDate: String
    let policyApproved: Bool
    let supportEmail: String
    let privacyURL: URL
    let supportURL: URL
    let supportPageURL: URL
    let termsURL: URL
    let notices: [Notice]
  }
  enum LinkKind: Sendable { case privacy, support, supportPage, terms }
  let manifest: Manifest
  let supportEmailURL: URL
  private let documents: [InformationDocumentID: InformationDocument]
  static var displayName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PocketWork" }
  static var version: ProductVersion? { ProductVersion(info: Bundle.main.infoDictionary ?? [:]) }

  static func load(directory: URL? = nil) throws -> Self {
    let root: URL
    if let directory { root = directory }
    else {
      #if SWIFT_PACKAGE
        let bundle = Bundle.module
      #else
        let bundle = Bundle.main
      #endif
      guard let url = bundle.url(forResource: "Information", withExtension: nil) else { throw InformationError.missingResource }
      root = url
    }
    let manifest: Manifest
    do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appending(path: "manifest.json"))) }
    catch { throw InformationError.invalidMetadata }
    guard manifest.schemaVersion == 1, manifest.displayName == "PocketWork",
      manifest.publisher == "Salty Panda LLC",
      manifest.policyVersion.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.[0-9]+$", options: .regularExpression) != nil,
      validDate(manifest.effectiveDate), !manifest.notices.isEmpty,
      Set(manifest.notices.map(\.id)).count == manifest.notices.count,
      manifest.notices.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && !$0.license.isEmpty }) else {
      throw InformationError.invalidMetadata
    }
    _ = try publicURL(manifest.privacyURL.absoluteString, kind: .privacy)
    _ = try publicURL(manifest.supportURL.absoluteString, kind: .support)
    _ = try publicURL(manifest.supportPageURL.absoluteString, kind: .supportPage)
    _ = try publicURL(manifest.termsURL.absoluteString, kind: .terms)
    let supportEmailURL = try supportEmailURL(manifest.supportEmail)
    var documents: [InformationDocumentID: InformationDocument] = [:]
    for id in InformationDocumentID.allCases {
      guard let bytes = try? Data(contentsOf: root.appending(path: id.filename)), bytes.count <= 131072,
        let text = String(data: bytes, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw InformationError.missingResource
      }
      documents[id] = InformationDocument(id: id, text: text)
    }
    guard documents[.privacy]?.text.contains(manifest.effectiveDate) == true,
      documents[.privacy]?.text.contains(manifest.policyVersion) == true else { throw InformationError.invalidMetadata }
    return Self(manifest: manifest, supportEmailURL: supportEmailURL, documents: documents)
  }
  func document(_ id: InformationDocumentID) -> InformationDocument { documents[id]! }
  func validateForPublicRelease() throws {
    guard manifest.policyApproved else { throw InformationError.policyNeedsApproval }
  }
  static func supportEmailURL(_ address: String) throws -> URL {
    guard address == "support@saltypanda.com", let url = URL(string: "mailto:" + address) else {
      throw InformationError.invalidURL
    }
    return url
  }
  static func publicURL(_ value: String, kind: LinkKind) throws -> URL {
    guard let c = URLComponents(string: value), c.scheme == "https", c.user == nil, c.password == nil,
      c.port == nil, c.query == nil, c.fragment == nil, let url = c.url else { throw InformationError.invalidURL }
    let expected: String
    switch kind {
    case .privacy: expected = "https://bitl8-byteshort.github.io/openwork-remote-ios/privacy/"
    case .support: expected = "https://github.com/BitL8-ByteShort/openwork-remote-ios/issues"
    case .supportPage: expected = "https://bitl8-byteshort.github.io/openwork-remote-ios/support/"
    case .terms: expected = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    }
    guard value == expected else { throw InformationError.invalidURL }
    return url
  }
  private static func validDate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return value.count == 10 && formatter.date(from: value).map { formatter.string(from: $0) == value } == true
  }
}
