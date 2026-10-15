import Foundation
import Observation
import OpenWorkRemoteCore

struct NativeAttachmentContext:Hashable,Identifiable,Sendable {
  let target:OpenCodeTarget
  let id:UUID
}
@MainActor @Observable final class NativeAttachmentStore {
  let journal:NativeConversationJournal
  let files:ProtectedAttachmentFiles
  private(set) var context:NativeAttachmentContext?
  var notice:String?
  @ObservationIgnored private var client:(any OpenCodeFileServing)?
  @ObservationIgnored private var connection:ConnectionID?
  @ObservationIgnored private var mutationEpoch=UUID()
  @ObservationIgnored private var preparations:[UUID:(id:UUID,task:Task<OpenCodePromptFile,any Error>)]=[:]
  @ObservationIgnored private var cancelledPreparations=Set<UUID>()
  init(journal:NativeConversationJournal,files:ProtectedAttachmentFiles){self.journal=journal;self.files=files}
  var rows:[NativeSelectedAttachment]{context.map{journal.attachments(for:$0.target)} ?? []}
  var canChoose:Bool{context.map{journal.ready && !journal.storageIssue && journal.pending(for:$0.target)==nil && rows.count<4} ?? false}
  var canSend:Bool{!rows.isEmpty && rows.allSatisfy{$0.phase == .ready} && context.map{journal.pending(for:$0.target)==nil} == true}
  @discardableResult func activate(target:OpenCodeTarget,client:any OpenCodeFileServing)->NativeAttachmentContext{
    if connection != target.connectionID{mutationEpoch=UUID();connection=target.connectionID}
    let context=NativeAttachmentContext(target:target,id:UUID());self.context=context;self.client=client;notice=nil;return context
  }
  func clearSelection(){context=nil;client=nil;notice=nil}
  func deactivate(){
    mutationEpoch=UUID();connection=nil
    for preparation in preparations.values{preparation.task.cancel()}
    preparations=[:];cancelledPreparations=[];clearSelection()
  }
  func cancelPreparation(_ id:UUID,context:NativeAttachmentContext){
    guard self.context==context,journal.pending(for:context.target)==nil,rows.contains(where:{$0.id==id && $0.phase == .preparing}) else{return}
    cancelledPreparations.insert(id);preparations[id]?.task.cancel()
  }
  func add(_ file:LocalAttachmentFile,context:NativeAttachmentContext) async throws{
    guard self.context==context,canChoose else{throw RemoteError.unavailable}
    try await files.verify(file)
    guard self.context==context,canChoose else{throw RemoteError.cancelled}
    try await journal.setAttachments(rows+[NativeSelectedAttachment(file:file)],for:context.target)
    await prepare(file.id,context:context)
  }
  /// Explicit retry always uses a fresh native upload UUID; never resumes an uncertain path.
  func prepare(_ id:UUID,context:NativeAttachmentContext) async{
    guard self.context==context,let client,journal.pending(for:context.target)==nil,
      var row=rows.first(where:{$0.id==id}),row.phase != .preparing,row.phase != .ready else{return}
    let epoch=mutationEpoch;row.phase = .preparing;row.prepared=nil
    notice=nil
    do{
      try await update(row,target:context.target)
      guard epoch==mutationEpoch,!Task.isCancelled else{return}
      if cancelledPreparations.remove(id) != nil{row.phase = .failed;try await update(row,target:context.target);return}
      let file=row.file,localFiles=files,operation=UUID()
      let task=Task{
        try Task.checkCancellation()
        let bytes=try await localFiles.read(file)
        let model=try await client.attachmentModel(target:context.target)
        try Task.checkCancellation()
        return try await client.prepareAttachment(bytes:bytes,name:file.name,mime:file.mime,target:context.target,model:model)
      }
      preparations[id]=(operation,task)
      defer{
        if preparations[id]?.id==operation{preparations.removeValue(forKey:id);cancelledPreparations.remove(id)}
      }
      let prepared=try await task.value
      guard epoch==mutationEpoch else{return}
      row.prepared=prepared;row.phase = .ready;try await update(row,target:context.target)
    }catch{
      guard epoch==mutationEpoch else{return}
      let needsReview=error is NativeSharingReviewRequired
      row.prepared=nil;row.phase=needsReview ? .selected : error as? RemoteError == .outcomeUnknown ? .uploadUnknown : .failed
      do{try await update(row,target:context.target)}catch{}
      if self.context==context{
        if needsReview{notice="Review sharing permission, then tap Retry to prepare this file."}
        else{notice=row.phase == .uploadUnknown ? "The computer may have a temporary copy. Prepare a new copy only if you want to retry; it will use a different temporary path." : "This file could not be prepared. Check the connection and current model, then try again."}
      }
    }
  }
  func remove(_ id:UUID,context:NativeAttachmentContext) async{
    guard self.context==context,journal.pending(for:context.target)==nil,let row=rows.first(where:{$0.id==id}),row.phase != .preparing else{return}
    do{try await journal.setAttachments(rows.filter{$0.id != id},for:context.target);try await files.remove(row.file)}
    catch{notice="The selected file or its local copy could not be removed. Unlock this device and try again."}
  }
  func promptFiles(context:NativeAttachmentContext) async throws->[OpenCodePromptFile]{
    guard self.context==context,journal.pending(for:context.target)==nil else{throw RemoteError.unavailable}
    let snapshot=rows
    guard snapshot.allSatisfy({$0.phase == .ready && $0.prepared != nil}) else{throw RemoteError.unavailable}
    var values:[OpenCodePromptFile]=[]
    for row in snapshot{values.append(try await row.prepared!.withBytes(files.read(row.file)))}
    guard self.context==context,rows.map(\.id)==snapshot.map(\.id) else{throw RemoteError.cancelled}
    return values
  }
  private func update(_ row:NativeSelectedAttachment,target:OpenCodeTarget) async throws{
    var rows=journal.attachments(for:target)
    guard let index=rows.firstIndex(where:{$0.id==row.id}) else{return}
    rows[index]=row;try await journal.setAttachments(rows,for:target)
  }
}
