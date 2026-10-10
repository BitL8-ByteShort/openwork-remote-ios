import Foundation

struct DataResetReport: Equatable, Sendable, Identifiable {
  enum HostRevocation: Sendable { case revoked, unconfirmed, noConnection }
  let id = UUID()
  let localFailures: [String]
  let hostRevocation: HostRevocation
  var summary: String {
    let local = localFailures.isEmpty
      ? "Your saved pairing, local drafts and app file copies were removed."
      : "Pairing was removed, but some local data could not be removed: " + localFailures.joined(separator: ", ") + ". Unlock the phone and try local reset again."
    let remote: String
    switch hostRevocation {
    case .revoked: remote = "This phone's access was revoked on the computer."
    case .unconfirmed: remote = "Revoke this phone in OpenWork on your computer when it is online. Its saved device grant may remain."
    case .noConnection: remote = "If you previously paired this phone, check its saved device grant in OpenWork on that computer."
    }
    return local + " " + remote + " Your computer's chats and original files were not deleted."
  }
}
