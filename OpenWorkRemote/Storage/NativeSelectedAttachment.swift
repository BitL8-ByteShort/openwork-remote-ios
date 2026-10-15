import Foundation
import OpenWorkRemoteCore

enum NativeAttachmentPhase:String,Codable,Sendable {case selected,preparing,ready,failed,uploadUnknown}
struct NativeSelectedAttachment:Codable,Sendable,Identifiable {
  let file:LocalAttachmentFile
  var phase:NativeAttachmentPhase = .selected
  var prepared:OpenCodePromptFile?
  var id:UUID{file.id}
  func validate(target:OpenCodeTarget)throws{
    guard !target.projectID.isEmpty,target.projectID.utf8.count<=2_048,target.sessionID.hasPrefix("ses"),target.sessionID.utf8.count<=2_048,
      target.directory.hasPrefix("/"),target.directory.utf8.count<=8_192,!target.directory.contains("\0") else{throw RemoteError.invalidResponse}
    try AttachmentValidation.metadata(name:file.name,mime:file.mime,bytes:file.bytes,sha256:file.sha256)
    guard ["image/png","application/pdf"].contains(file.mime),(phase == .ready)==(prepared != nil) else{throw RemoteError.invalidResponse}
    if let prepared{
      guard prepared.target==target,prepared.bytes==file.bytes,prepared.sha256==file.sha256,prepared.mime==file.mime else{throw RemoteError.conflict}
    }
  }
}
