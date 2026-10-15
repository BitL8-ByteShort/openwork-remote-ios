import Foundation
import Observation
import OpenWorkRemoteCore

enum NativeNavigationIssue { case unavailable,locationChanged,projectUnavailable,sessionUnavailable }
@MainActor @Observable final class OpenCodeNavigationStore {
  private(set) var projects:[OpenCodeProject]=[]
  private(set) var sessions:[OpenCodeSession]=[]
  private(set) var selectedProjectID:String?
  private(set) var selectedSession:OpenCodeSession?
  private(set) var messages:[OpenCodeMessage]=[]
  private(set) var target:OpenCodeTarget?
  private(set) var loadingProjects=false
  private(set) var loadingSessions=false
  private(set) var loadingMessages=false
  private(set) var loadingOlder=false
  private(set) var issue:NativeNavigationIssue?
  private(set) var windowTruncated=false
  private(set) var hasNewReplies=false
  @ObservationIgnored private var lastNativeSnapshot:[OpenCodeMessage]=[]
  @ObservationIgnored private var latestNativePage:OpenCodeMessagePage?
  private(set) var sessionCursor:String?
  private(set) var olderCursor:String?
  private(set) var preserveScrollAnchor:String?
  @ObservationIgnored private let maximumMessages:Int
  @ObservationIgnored private var connection:OpenCodeConnection?
  @ObservationIgnored private var reader:(any OpenCodeHistoryReading)?
  @ObservationIgnored private var generation=UUID()
  @ObservationIgnored private var selection=UUID()
  @ObservationIgnored private var seenHistoryCursors=Set<String>()

  init(maximumMessages:Int=600) { self.maximumMessages=max(1,min(maximumMessages,2_000)) }
  func activate(_ connection:OpenCodeConnection,reader:any OpenCodeHistoryReading) {
    generation=UUID(); selection=UUID(); self.connection=connection;self.reader=reader
    projects=[];sessions=[];messages=[];selectedProjectID=nil;selectedSession=nil;target=nil
    issue=nil;olderCursor=nil;sessionCursor=nil;seenHistoryCursors=[]
    loadingProjects=false;loadingSessions=false;loadingMessages=false;loadingOlder=false
    windowTruncated=false;preserveScrollAnchor=nil;hasNewReplies=false;lastNativeSnapshot=[];latestNativePage=nil
  }
  func deactivate(){
    generation=UUID();selection=UUID();connection=nil;reader=nil
    projects=[];sessions=[];messages=[];selectedProjectID=nil;selectedSession=nil;target=nil
    issue=nil;olderCursor=nil;sessionCursor=nil;seenHistoryCursors=[]
    loadingProjects=false;loadingSessions=false;loadingMessages=false;loadingOlder=false
    windowTruncated=false;preserveScrollAnchor=nil;hasNewReplies=false;lastNativeSnapshot=[];latestNativePage=nil
  }
  func showLatestSnapshot(){
    guard let target,let session=selectedSession,let page=latestNativePage else{return}
    acceptNativeSnapshot(target:target,session:session,page:page,preserveWindow:false)
  }
  /// The selected row appears immediately; writes still require authoritative verification.
  func selectProvisional(_ session:OpenCodeSession)->OpenCodeTarget? {
    guard let connection,session.projectID==selectedProjectID,session.time.archived==nil else{return nil}
    selection=UUID();selectedSession=session;messages=[];olderCursor=nil;seenHistoryCursors=[]
    loadingMessages=true;loadingOlder=false;issue=nil;windowTruncated=false;preserveScrollAnchor=nil
    hasNewReplies=false;lastNativeSnapshot=[];latestNativePage=nil
    let value=OpenCodeTarget(connectionID:connection.id,projectID:session.projectID,sessionID:session.id,directory:session.location.directory)
    target=value;return value
  }
  func acceptNativeSnapshot(target:OpenCodeTarget,session:OpenCodeSession,page:OpenCodeMessagePage,preserveWindow:Bool){
    guard self.target==target,session.id==target.sessionID,session.projectID==target.projectID,
      OpenCodeIdentity.matches(session.location.directory,target.directory),session.time.archived==nil else{return}
    selectedSession=session;loadingMessages=false;issue=nil
    if let index=sessions.firstIndex(where:{$0.id==session.id}){sessions[index]=session}
    if preserveWindow,!messages.isEmpty {
      hasNewReplies = hasNewReplies || page.data != lastNativeSnapshot
      let updates=Dictionary(uniqueKeysWithValues:page.data.map{($0.id,$0)})
      messages=messages.map{updates[$0.id] ?? $0}
    }else{
      messages=[];merge(page.data,older:false);olderCursor=page.cursor.next;seenHistoryCursors=[];hasNewReplies=false
    }
    lastNativeSnapshot=page.data;latestNativePage=page
  }
  func finishNativeRead(target:OpenCodeTarget,failed:Bool){
    guard self.target==target else{return};loadingMessages=false
    if failed{issue = .unavailable}
  }
  func removeChats(_ ids:Set<String>){
    sessions.removeAll{ids.contains($0.id)}
    if let target,ids.contains(target.sessionID){
      selection=UUID();selectedSession=nil;self.target=nil;messages=[];olderCursor=nil;seenHistoryCursors=[]
      loadingMessages=false;loadingOlder=false;hasNewReplies=false;lastNativeSnapshot=[];latestNativePage=nil
    }
  }
  func acceptChat(_ session:OpenCodeSession){
    guard session.projectID==selectedProjectID,session.time.archived==nil else{return}
    if let i=sessions.firstIndex(where:{$0.id==session.id}){sessions[i]=session}else{sessions.insert(session,at:0)}
    if let target,target.sessionID==session.id,OpenCodeIdentity.matches(target.directory,session.location.directory){selectedSession=session}
  }
  func refreshProjects() async {
    guard let reader else { return }
    let current=generation
    loadingProjects=true
    defer { if current==generation { loadingProjects=false } }
    do {
      let result=try await reader.projects()
      guard current==generation,!Task.isCancelled else{return}
      projects=result.filter{$0.time.archived == nil}
      if let selectedProjectID {
        if !projects.contains(where:{$0.id==selectedProjectID}) {
          selection=UUID();self.selectedProjectID=nil;selectedSession=nil;target=nil;sessions=[];messages=[]
          issue = .projectUnavailable
        }
      } else if let first=projects.first { await selectProject(first.id) }
    } catch { if current==generation { issue = .unavailable } }
  }
  func selectProject(_ id:String) async {
    guard let reader,projects.contains(where:{$0.id==id}) else{return}
    selection=UUID(); let picked=selection, current=generation
    selectedProjectID=id;selectedSession=nil;target=nil;messages=[];sessions=[]
    sessionCursor=nil;olderCursor=nil;issue=nil;loadingSessions=true;loadingMessages=false;loadingOlder=false;hasNewReplies=false;lastNativeSnapshot=[];latestNativePage=nil
    defer { if current==generation,picked==selection { loadingSessions=false } }
    do {
      let page=try await reader.sessions(projectID:id,cursor:nil,search:nil)
      guard current==generation,picked==selection,!Task.isCancelled else{return}
      sessions=page.data;sessionCursor=page.cursor.next
    } catch { if current==generation,picked==selection { issue = .unavailable } }
  }
  func loadMoreSessions() async {
    guard !loadingSessions,let reader,let id=selectedProjectID,let cursor=sessionCursor else{return}
    let current=generation,picked=selection;loadingSessions=true
    defer { if current==generation,picked==selection {loadingSessions=false} }
    do {
      let page=try await reader.sessions(projectID:id,cursor:cursor,search:nil)
      guard current==generation,picked==selection,!Task.isCancelled else{return}
      guard page.cursor.next != cursor else{throw RemoteError.invalidResponse}
      var existing=Set(sessions.map(\.id));sessions.append(contentsOf:page.data.filter{existing.insert($0.id).inserted})
      if sessions.count>1_000 {sessions=Array(sessions.suffix(1_000))}
      sessionCursor=page.cursor.next
    } catch {if current==generation,picked==selection {issue = .unavailable}}
  }
  func open(_ session:OpenCodeSession) async {
    guard let reader,let connection,session.projectID==selectedProjectID else{return}
    selection=UUID();let picked=selection,current=generation
    selectedSession=session;messages=[];target=nil;olderCursor=nil;seenHistoryCursors=[]
    loadingMessages=true;loadingOlder=false;issue=nil;windowTruncated=false;preserveScrollAnchor=nil
    defer {if current==generation,picked==selection {loadingMessages=false}}
    do {
      async let readSession=reader.session(id:session.id)
      async let readMessages=reader.messages(sessionID:session.id,cursor:nil)
      let (authoritative,page)=try await (readSession,readMessages)
      guard current==generation,picked==selection,!Task.isCancelled else{return}
      guard authoritative.projectID==session.projectID,authoritative.location==session.location,
        authoritative.time.archived==nil else {issue = .locationChanged;return}
      selectedSession=authoritative
      target=OpenCodeTarget(connectionID:connection.id,projectID:session.projectID,sessionID:session.id,directory:authoritative.location.directory)
      merge(page.data,older:false);olderCursor=page.cursor.next
    } catch {
      if current==generation,picked==selection {
        issue = error as? RemoteError == .notFound ? .sessionUnavailable : .unavailable
      }
    }
  }
  func loadOlder() async {
    guard !loadingOlder,let reader,let target,let cursor=olderCursor else{return}
    let current=generation,picked=selection;loadingOlder=true
    defer {if current==generation,picked==selection {loadingOlder=false}}
    do {
      guard !seenHistoryCursors.contains(cursor) else{throw RemoteError.invalidResponse}
      let page=try await reader.messages(sessionID:target.sessionID,cursor:cursor)
      guard current==generation,picked==selection,!Task.isCancelled else{return}
      guard page.cursor.next != cursor else{throw RemoteError.invalidResponse}
      seenHistoryCursors.insert(cursor);preserveScrollAnchor=messages.first?.id
      merge(page.data,older:true);olderCursor=page.cursor.next
    } catch {if current==generation,picked==selection {issue = .unavailable}}
  }
  private func merge(_ incoming:[OpenCodeMessage],older:Bool) {
    var byID=Dictionary(uniqueKeysWithValues:messages.map{($0.id,$0)})
    for item in incoming {byID[item.id]=item}
    // The API owns projection order. Re-sorting by timestamp/ID changes it when
    // timestamps match or when a client supplied a non-sortable native ID.
    let existing=Set(messages.map(\.id))
    let added=incoming.reversed().filter{!existing.contains($0.id)}.map(\.id)
    let ordered=older ? added+messages.map(\.id) : messages.map(\.id)+added
    messages=ordered.compactMap{byID[$0]}
    var bytes=messages.reduce(0){$0+$1.storedTextBytes}
    while !messages.isEmpty && (messages.count>maximumMessages || bytes>8_388_608) {
      let removed=older ? messages.removeLast() : messages.removeFirst()
      bytes-=removed.storedTextBytes;windowTruncated=true
    }
  }
}
