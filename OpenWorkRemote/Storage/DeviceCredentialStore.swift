import Foundation
import Security

struct StoredPairing: Codable, Sendable {
  let origin: String
  let token: String
  let hostId: String
}
enum DeviceCredentialStore {
  private static let service = "com.saltypanda.openworkremote.pairing"
  static func load() throws -> StoredPairing? {
    var result: CFTypeRef?
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return try JSONDecoder().decode(StoredPairing.self, from: data)
  }
  static func save(_ pairing: StoredPairing) throws {
    let data = try JSONEncoder().encode(pairing)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      attributes.forEach { item[$0] = $1 }
      let result = SecItemAdd(item as CFDictionary, nil)
      guard result == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
      }
    } else if status != errSecSuccess {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
  static func remove() throws {
    let result = SecItemDelete(
      [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        as CFDictionary)
    guard result == errSecSuccess || result == errSecItemNotFound else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
    }
  }
}

/// Storage boundary shared by startup, pairing and access recovery.
@MainActor struct PairingPersistence {
  var load: () throws -> StoredPairing?
  var save: (StoredPairing) throws -> Void
  var remove: () throws -> Void
  static let keychain = PairingPersistence(
    load: DeviceCredentialStore.load, save: DeviceCredentialStore.save,
    remove: DeviceCredentialStore.remove)
}
