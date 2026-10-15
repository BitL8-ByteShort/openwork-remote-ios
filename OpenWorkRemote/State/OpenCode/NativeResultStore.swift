import Foundation
import Observation
import OpenWorkRemoteCore

struct NativeResultContext:Hashable,Identifiable,Sendable {
  let target:OpenCodeTarget
  let id:UUID
}
@MainActor @Observable final class NativeResultStore {
  let files:ProtectedArtifactFiles
  private(set) var context:NativeResultContext?
  private(set) var items:[OpenCodeResultFile]=[]
  private(set) var unsupportedReferences=0
  private(set) var ready:NativeLocalArtifact?
  private(set) var preview:ArtifactPreviewData?
  private(set) var downloading=false
  private(set) var loadingPage=false
  private(set) var notice:String?
  @ObservationIgnored private var client:(any OpenCodeResultServing)?
  @ObservationIgnored private var downloadID=UUID()
  @ObservationIgnored private var pageID=UUID()
  @ObservationIgnored private var task:Task<Void,Never>?
  init(files:ProtectedArtifactFiles){self.files=files}
  var canShare:Bool{ready != nil && preview != nil && !downloading && !loadingPage}
  @discardableResult func activate(target:OpenCodeTarget,client:any OpenCodeResultServing)->NativeResultContext{
    deactivate()
    let value=NativeResultContext(target:target,id:UUID());context=value;self.client=client;return value
  }
  func deactivate(){closePreview();context=nil;client=nil;items=[];unsupportedReferences=0;notice=nil}
  func updateReferences(_ messages:[OpenCodeMessage],target:OpenCodeTarget){
    guard context?.target==target else{return}
    let catalog=OpenCodeResultCatalog(messages:messages,target:target)
    items=catalog.files;unsupportedReferences=catalog.unsupportedReferences
  }
  func closePreview(){
    downloadID=UUID();pageID=UUID();task?.cancel();task=nil
    let previous=ready;ready=nil;preview=nil;downloading=false;loadingPage=false
    if let previous{Task{try? await files.remove(previous)}}
  }
  func open(_ file:OpenCodeResultFile,context:NativeResultContext) async{
    guard self.context==context,file.target==context.target,let client else{return}
    closePreview();notice=nil;downloading=true
    let run=downloadID,files=self.files
    let work=Task{[weak self] in
      var local:NativeLocalArtifact?
      var writingCache=false
      do{
        let info=try await client.probeResult(file)
        let download=try await client.downloadResult(info)
        try Task.checkCancellation()
        guard let self,self.context==context,self.downloadID==run else{return}
        writingCache=true
        let copy=try await files.storeNative(download);local=copy
        try Task.checkCancellation()
        let rendered=try await files.preview(copy)
        guard self.context==context,self.downloadID==run,!Task.isCancelled else{try? await files.remove(copy);return}
        self.ready=copy;self.preview=rendered;self.downloading=false
      }catch{
        if let local{try? await files.remove(local)}
        guard let self,self.context==context,self.downloadID==run else{return}
        self.downloading=false
        if !(error is CancellationError){self.notice=writingCache && error as? RemoteError == .oversized ? "Temporary download storage is full. Clear downloaded files in Settings, then try again.":self.failure(error)}
      }
    }
    task=work;await work.value
    if self.context==context,downloadID==run{task=nil}
  }
  func showPage(_ page:Int,context:NativeResultContext) async{
    guard self.context==context,let ready,ready.info.previewKind == .pdf else{return}
    let run=UUID();pageID=run;loadingPage=true
    defer{if self.context==context,pageID==run{loadingPage=false}}
    do{
      let rendered=try await files.preview(ready,page:page)
      guard self.context==context,pageID==run,!Task.isCancelled else{return}
      preview=rendered
    }catch{if self.context==context,pageID==run{notice="This page could not be displayed. Check the PDF on your computer."}}
  }
  func projectFiles(directory:String?,context:NativeResultContext) async throws->[OpenCodeProjectFile]{
    guard self.context==context,let client else{throw RemoteError.cancelled}
    let entries=try await client.projectFiles(target:context.target,directory:directory)
    guard self.context==context,!Task.isCancelled else{throw RemoteError.cancelled}
    return entries
  }
  func prepareShare(context:NativeResultContext) async->URL?{
    guard self.context==context,canShare,let ready,let client else{return nil}
    let run=downloadID
    do{
      guard try await client.probeResult(ready.info.file)==ready.info else{throw RemoteError.conflict}
      try await files.verify(ready)
      guard self.context==context,downloadID==run,!Task.isCancelled else{return nil}
      return ready.url
    }catch{
      guard self.context==context,downloadID==run else{return nil}
      closePreview();notice="The file changed or could not be verified. Open it again before sharing.";return nil
    }
  }
  private func failure(_ error:any Error)->String{
    switch error as? RemoteError{
    case .unauthorized:return "OpenCode rejected this connection. Pair again with a fresh code."
    case .forbidden,.notFound:return "This file is missing or outside the selected project. Check it on your computer."
    case .conflict:return "The file or chat changed during the read. Open it again to download the current version."
    case .oversized:return "This file is too large for a preview. Files up to 20 MiB are supported."
    case .incompatible:return "This file type or an empty file needs your computer."
    default:return "The file could not be verified or downloaded. Check the connection, file type and free storage."
    }
  }
}
