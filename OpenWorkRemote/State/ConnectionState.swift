import Foundation

enum ConnectionState: String {
  case unpaired, pairing, connecting, ready, reconnecting, offline, revoked, incompatible
  var label: String {
    switch self {
    case .unpaired: return "Pair your computer"
    case .pairing: return "Waiting for your computer"
    case .connecting: return "Connecting…"
    case .ready: return "Connected"
    case .reconnecting: return "Reconnecting…"
    case .offline: return "Computer unavailable"
    case .revoked: return "Pairing was revoked"
    case .incompatible: return "Update required"
    }
  }
}
