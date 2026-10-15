import Foundation

struct DataResetReport: Equatable, Sendable, Identifiable {
  enum HostRevocation: Sendable { case revoked, unconfirmed, noConnection, nativeNotRevoked }
  let id = UUID()
  let localFailures: [String]
  let hostRevocation: HostRevocation
  let credentialsRemoved:Bool
  init(localFailures:[String],hostRevocation:HostRevocation,credentialsRemoved:Bool=true){
    self.localFailures=localFailures;self.hostRevocation=hostRevocation;self.credentialsRemoved=credentialsRemoved
  }
  var summary: String {
    let local = !credentialsRemoved ? "Some saved credentials could not be removed: "+localFailures.joined(separator:", ")+". Local files were kept. Unlock this device and retry reset."
      : localFailures.isEmpty
      ? "Your saved pairing, local drafts and app file copies were removed."
      : "Pairing was removed, but some local data could not be removed: " + localFailures.joined(separator: ", ") + ". Unlock the phone and try local reset again."
    let remote: String
    switch hostRevocation {
    case .revoked: remote = "This phone's access was revoked on the computer."
    case .unconfirmed: remote = "Revoke this phone in OpenWork on your computer when it is online. Its saved device grant may remain."
    case .noConnection: remote = "If you previously paired this phone, check its saved device grant in OpenWork on that computer."
    case .nativeNotRevoked:remote = "Server access was not revoked. Rotate the OpenCode server password on your computer to invalidate paired devices. If you used the earlier OpenWork beta, remove its device grant there."
    }
    return local + " " + remote + " Your computer's chats and original files were not deleted."
  }
}
