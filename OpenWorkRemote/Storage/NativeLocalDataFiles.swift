import Foundation

protocol NativeResettableSnapshot:Sendable{
  func retireWriter()async
  func invalidateAndRemove()async throws
}
extension NativeConversationFile:NativeResettableSnapshot{}
extension NativeFormFile:NativeResettableSnapshot{}
extension NativeVisibilityFile:NativeResettableSnapshot{}
extension NativeCreationFile:NativeResettableSnapshot{}
extension NativeActionFile:NativeResettableSnapshot{}
extension LocalChatGroupFile:NativeResettableSnapshot{}
extension LocalChatDefaultsFile:NativeResettableSnapshot{}
extension NativeSelectionFile:NativeResettableSnapshot{}
extension ProviderDisclosureFile:NativeResettableSnapshot{}

/// These are the same actor instances used by the live stores, not replacement
/// removers that leave an old autosave writer able to recreate a deleted file.
struct NativeLocalDataFiles:Sendable{
  let conversations:NativeConversationFile
  let forms:NativeFormFile
  let visibility:NativeVisibilityFile
  let creation:NativeCreationFile
  let actions:NativeActionFile
  let groups:LocalChatGroupFile
  let defaults:LocalChatDefaultsFile
  let selection:NativeSelectionFile
  let sharing:ProviderDisclosureFile
  init(directory:URL)throws{
    conversations=try NativeConversationFile(directory:directory)
    forms=try NativeFormFile(directory:directory)
    visibility=try NativeVisibilityFile(directory:directory)
    creation=try NativeCreationFile(directory:directory)
    actions=try NativeActionFile(directory:directory)
    groups=try LocalChatGroupFile(directory:directory)
    defaults=try LocalChatDefaultsFile(directory:directory)
    selection=NativeSelectionFile(directory:directory)
    sharing=ProviderDisclosureFile(directory:directory)
  }
  private var components:[(String,any NativeResettableSnapshot)]{
    [("OpenCode chat drafts, selected items and unconfirmed sends",conversations),
     ("OpenCode question drafts and reply records",forms),("Project visibility preferences",visibility),
     ("Unconfirmed chat creations",creation),("Unconfirmed chat actions",actions),
     ("Local chat groups",groups),("Local new-chat defaults",defaults),
     ("Last-opened project and chat",selection),("Sharing permissions",sharing)]
  }
  func retireWriters()async{for (_,file) in components{await file.retireWriter()}}
  func removeAll()async->[String]{
    var failures:[String]=[]
    for (label,file) in components{do{try await file.invalidateAndRemove()}catch{failures.append(label)}}
    return failures
  }
}
