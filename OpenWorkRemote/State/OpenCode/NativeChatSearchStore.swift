import Foundation
import Observation
import OpenWorkRemoteCore

@MainActor @Observable final class NativeChatSearchStore {
  private(set) var scope:NativeProjectKey?
  private(set) var query=""
  private(set) var results:[OpenCodeSession]=[]
  private(set) var cursor:String?
  private(set) var complete=false
  private(set) var loading=false
  private(set) var notice:String?
  @ObservationIgnored private var reader:(any OpenCodeSessionSearching)?
  @ObservationIgnored private var run=UUID()
  @ObservationIgnored private var cursors=Set<String>()
  func activate(_ scope:NativeProjectKey?,reader:(any OpenCodeSessionSearching)?){
    run=UUID();self.scope=scope;self.reader=reader;query="";results=[];cursor=nil;complete=false;loading=false;notice=nil;cursors=[]
  }
  func cancel(){run=UUID();loading=false}
  func search(_ text:String,debounce:Bool=true)async{
    run=UUID();let current=run
    query=text.trimmingCharacters(in:.whitespacesAndNewlines);results=[];cursor=nil;complete=false;loading=false;notice=nil;cursors=[]
    guard !query.isEmpty else{return}
    guard query.unicodeScalars.count<=200,query.utf8.count<=800,
      !query.unicodeScalars.contains(where:{$0.properties.generalCategory == .control || $0.properties.generalCategory == .format}) else{
      notice="Use a title search of up to 200 characters.";return
    }
    loading=true
    do{if debounce{try await Task.sleep(for:.milliseconds(300))};try Task.checkCancellation()}
    catch{if current==run{loading=false};return}
    await load(cursor:nil,current:current)
  }
  func more()async{
    guard !loading,let cursor else{return};loading=true;await load(cursor:cursor,current:run)
  }
  private func load(cursor next:String?,current:UUID)async{
    guard let scope,let reader else{loading=false;return}
    let capturedQuery=query
    defer{if current==run{loading=false}}
    do{
      let page=try await reader.sessions(projectID:scope.projectID,cursor:next,search:capturedQuery)
      guard self.scope==scope,current==run,!Task.isCancelled else{return}
      try page.cursor.validateForNativeSearch()
      guard page.data.count<=200,page.data.allSatisfy({OpenCodeIdentity.matches($0.projectID,scope.projectID)}) else{throw RemoteError.invalidResponse}
      if let cursor=page.cursor.next{guard cursor != next,!cursors.contains(cursor) else{throw RemoteError.invalidResponse}}
      if let next{cursors.insert(next)}
      for row in page.data where row.time.archived==nil{
        if let i=results.firstIndex(where:{OpenCodeIdentity.matches($0.id,row.id)}){results[i]=row}else{results.append(row)}
      }
      cursor=page.cursor.next;complete=cursor==nil;notice=nil
      if results.count>=2_000,!complete{results=Array(results.prefix(2_000));cursor=nil;notice="Many chats match. Narrow your title search to check more."}
    }catch{
      if self.scope==scope,current==run,!Task.isCancelled{
        if error as? RemoteError == .invalidResponse || error as? RemoteError == .conflict{cursor=nil}
        notice="The title search could not finish. Try again; loaded matches are kept."
      }
    }
  }
}
private extension OpenCodeCursor{
  func validateForNativeSearch()throws{
    guard [previous,next].compactMap({$0}).allSatisfy({!$0.isEmpty && $0.utf8.count<=16_384}) else{throw RemoteError.invalidResponse}
  }
}
