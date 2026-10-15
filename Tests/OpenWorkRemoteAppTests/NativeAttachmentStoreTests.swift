import Foundation
import CryptoKit
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeFileService:OpenCodeFileServing {
  var uploads=0
  var failure:RemoteError?
  var hold=false
  var continuation:CheckedContinuation<Void,Never>?
  func holdPreparation(){hold=true}
  func waitUntilHeld() async{while continuation==nil{await Task.yield()}}
  func release(){continuation?.resume();continuation=nil}
  func setFailure(_ error:RemoteError = .outcomeUnknown){failure=error}
  func attachmentModel(target:OpenCodeTarget) async throws -> OpenCodeModel{
    try JSONDecoder().decode(OpenCodeModel.self,from:Data(#"{"id":"model","providerID":"provider","modelID":"model","name":"Model","enabled":true,"status":"active","variants":[],"capabilities":{"tools":true,"input":["text","image"],"output":["text"]}}"#.utf8))
  }
  func prepareAttachment(bytes:Data,name:String,mime:String,target:OpenCodeTarget,model:OpenCodeModel) async throws -> OpenCodePromptFile{
    uploads+=1
    if hold{await withCheckedContinuation{continuation=$0};if Task.isCancelled{throw RemoteError.outcomeUnknown}}
    if let failure{throw failure}
    let value:[String:Any]=["id":UUID().uuidString,"target":try JSONSerialization.jsonObject(with:JSONEncoder().encode(target)),"name":name,"mime":mime,"bytes":bytes.count,"sha256":SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),"placement":"inline"]
    return try JSONDecoder().decode(OpenCodePromptFile.self,from:JSONSerialization.data(withJSONObject:value))
  }
  func count()->Int{uploads}
}
@Suite @MainActor struct NativeAttachmentStoreTests {
  private let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=")!
  @Test func serverPermissionDenialStillReportsPreparationFailure()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-files-denied-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let journal=NativeConversationJournal(persistence:try NativeConversationFile(directory:root));try await journal.restore()
    let files=ProtectedAttachmentFiles(directory:root.appending(path:"bytes")),service=NativeFileService()
    await service.setFailure(.forbidden)
    let store=NativeAttachmentStore(journal:journal,files:files)
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let context=store.activate(target:target,client:service)
    try await store.add(files.savePhotoPNG(png),context:context)
    #expect(store.rows.first?.phase == .failed)
    #expect(store.notice=="This file could not be prepared. Check the connection and current model, then try again.")
    #expect(!store.canSend)
  }
  @Test(.timeLimit(.minutes(1))) func resetDuringPreparationCannotRecreateSelectedBytesOrJournal()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-reset-preparation-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let persistence=try NativeConversationFile(directory:root),journal=NativeConversationJournal(persistence:persistence)
    try await journal.restore()
    let bytes=root.appending(path:"bytes"),files=ProtectedAttachmentFiles(directory:bytes),service=NativeFileService()
    let store=NativeAttachmentStore(journal:journal,files:files)
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let context=store.activate(target:target,client:service),file=try await files.savePhotoPNG(png)
    await service.holdPreparation();let preparing=Task{try await store.add(file,context:context)}
    await service.waitUntilHeld();store.deactivate();journal.retire()
    await persistence.retireWriter();await files.retire()
    try await persistence.invalidateAndRemove();try await files.invalidateAndRemove()
    await service.release();try await preparing.value
    #expect(!FileManager.default.fileExists(atPath:root.appending(path:"native-conversations.json").path))
    #expect(try FileManager.default.contentsOfDirectory(atPath:bytes.path).isEmpty)
    let fresh=NativeConversationJournal(persistence:try NativeConversationFile(directory:root));try await fresh.restore()
    #expect(fresh.attachments(for:target).isEmpty)
    #expect(await service.count()==1)
  }
  @Test func selectedBytesSurviveRelaunchAndOnlyConfirmedFilesClear() async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-files-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let persistence=try NativeConversationFile(directory:root),journal=NativeConversationJournal(persistence:persistence)
    try await journal.restore()
    let files=ProtectedAttachmentFiles(directory:root.appending(path:"bytes")),service=NativeFileService()
    let store=NativeAttachmentStore(journal:journal,files:files)
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let context=store.activate(target:target,client:service)
    let file=try await files.savePhotoPNG(png)
    try await store.add(file,context:context)
    #expect(store.rows.count==1);#expect(store.canSend)
    let prepared=try await store.promptFiles(context:context)
    #expect(try prepared[0].inlineURI().hasPrefix("data:image/png;base64,"))
    let pending=try await journal.prepare(target:target,files:prepared)
    #expect(!store.canChoose)
    await store.remove(file.id,context:context)
    #expect(store.rows.count==1)
    let encoded=try JSONEncoder().encode(await persistence.load())
    #expect(!String(decoding:encoded,as:UTF8.self).contains(png.base64EncodedString()))
    let restored=NativeConversationJournal(persistence:persistence);try await restored.restore()
    let recovered=NativeAttachmentStore(journal:restored,files:files),recoveredContext=recovered.activate(target:target,client:service)
    #expect(recovered.rows.count==1);#expect(!recovered.canChoose)
    try await restored.reject(try #require(restored.pending(for:target)))
    #expect(try await recovered.promptFiles(context:recoveredContext).count==1)
    let retry=try await restored.prepare(target:target,files:recovered.promptFiles(context:recoveredContext))
    try await restored.confirm(retry)
    #expect(recovered.rows.isEmpty)
    #expect(journal.pending(for:target)?.prompt.id==pending.prompt.id)
  }
  @Test func unknownUploadIsNotRetriedOnRefreshOrRelaunch() async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-files-unknown-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let persistence=try NativeConversationFile(directory:root),journal=NativeConversationJournal(persistence:persistence)
    try await journal.restore()
    let files=ProtectedAttachmentFiles(directory:root.appending(path:"bytes")),service=NativeFileService()
    await service.setFailure()
    let store=NativeAttachmentStore(journal:journal,files:files)
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let context=store.activate(target:target,client:service)
    try await store.add(files.savePhotoPNG(png),context:context)
    #expect(store.rows.first?.phase == .uploadUnknown);#expect(!store.canSend)
    let restored=NativeConversationJournal(persistence:persistence);try await restored.restore()
    let recovered=NativeAttachmentStore(journal:restored,files:files)
    _=recovered.activate(target:target,client:service)
    #expect(recovered.rows.first?.phase == .uploadUnknown)
    #expect(await service.count()==1)
    await recovered.prepare(recovered.rows[0].id,context:context)
    #expect(await service.count()==1) // obsolete presentation cannot retry
  }
  @Test(.timeLimit(.minutes(1))) func cancelAndNavigationNeverAttachToTheNextChat() async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:"native-files-switch-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let journal=NativeConversationJournal(persistence:try NativeConversationFile(directory:root));try await journal.restore()
    let files=ProtectedAttachmentFiles(directory:root.appending(path:"bytes")),service=NativeFileService()
    let store=NativeAttachmentStore(journal:journal,files:files)
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    let context=store.activate(target:target,client:service),file=try await files.savePhotoPNG(png)
    await service.holdPreparation()
    let adding=Task{try await store.add(file,context:context)}
    await service.waitUntilHeld()
    store.cancelPreparation(file.id,context:context)
    let other=OpenCodeTarget(connectionID:target.connectionID,projectID:"project",sessionID:"ses_other",directory:"/project")
    _=store.activate(target:other,client:service)
    await service.release();try await adding.value
    #expect(store.rows.isEmpty)
    #expect(journal.attachments(for:target).first?.phase == .uploadUnknown)
    #expect(journal.attachments(for:other).isEmpty)
    #expect(await service.count()==1)
  }
  @Test func olderJournalDecodesAndOversizedMetadataFailsBeforeSummation() throws{
    var raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(NativeConversationDisk())) as! [String:Any]
    raw.removeValue(forKey:"attachments")
    let old=try JSONDecoder().decode(NativeConversationDisk.self,from:JSONSerialization.data(withJSONObject:raw));try old.validate()
    var value=NativeConversationDisk()
    let target=OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")
    value.attachments[target]=(0..<2).map{_ in NativeSelectedAttachment(file:LocalAttachmentFile(id:UUID(),name:"Photo.png",mime:"image/png",bytes:Int.max,sha256:String(repeating:"a",count:64)))}
    #expect(throws:(any Error).self){try value.validate()}
  }

}
