import Foundation
import OpenWorkRemoteCore

struct NativeSelectedSkill:Codable,Sendable,Equatable,Identifiable {
  let id:String
  let name:String
  let fingerprint:String
  init(_ skill:OpenCodeSkill){id=skill.id;name=skill.name;fingerprint=skill.fingerprint}
  func validate()throws{
    guard !id.isEmpty,id.utf8.count<=2_048,!name.isEmpty,name.utf8.count<=4_096,
      fingerprint.utf8.count==64,fingerprint.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}) else{throw RemoteError.invalidResponse}
  }
}
