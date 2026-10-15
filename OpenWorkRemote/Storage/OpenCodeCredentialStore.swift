import Foundation
import OpenWorkRemoteCore
import Security

struct StoredOpenCodeConnection: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  let connection: OpenCodeConnection
  let token: String
  var description: String { "OpenCode stored credential (redacted)" }
  var debugDescription: String { description }
}
@MainActor struct OpenCodePersistence {
  var load: () throws -> StoredOpenCodeConnection?
  var save: (StoredOpenCodeConnection) throws -> Void
  var remove: () throws -> Void
  static let keychain = OpenCodePersistence(load: OpenCodeCredentialStore.load,
    save: OpenCodeCredentialStore.save, remove: OpenCodeCredentialStore.remove)
}

/// Metadata and token change together in one Keychain item. No plaintext active-pointer
/// file or delete-before-add window can strand the previous connection on an update.
enum OpenCodeCredentialStore {
  static let service = "com.saltypanda.pocketwork.opencode-v2.connection"
  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: "active"]
  }
  static func load() throws -> StoredOpenCodeConnection? {
    var q = query, result: CFTypeRef?
    q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let bytes = result as? Data else { throw failure(status) }
    guard bytes.count <= 65_536 else { throw RemoteError.invalidResponse }
    let value = try JSONDecoder().decode(StoredOpenCodeConnection.self, from: bytes)
    try validate(value)
    return value
  }
  static func save(_ value: StoredOpenCodeConnection) throws {
    try validate(value)
    let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query; attributes.forEach { item[$0] = $1 }
      let added = SecItemAdd(item as CFDictionary, nil)
      guard added == errSecSuccess else { throw failure(added) }
    } else if status != errSecSuccess { throw failure(status) }
  }
  static func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
  }
  private static func failure(_ status: OSStatus) -> NSError {
    NSError(domain: NSOSStatusErrorDomain, code: Int(status))
  }
  private static func validate(_ value: StoredOpenCodeConnection) throws {
    guard !value.token.isEmpty, value.token.utf8.count <= 16_384,
      !value.token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw RemoteError.invalidPairing
    }
  }
}
