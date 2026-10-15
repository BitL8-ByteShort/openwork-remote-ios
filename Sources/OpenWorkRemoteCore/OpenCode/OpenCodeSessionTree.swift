import Foundation

public struct OpenCodeSessionTree:Codable,Sendable,Equatable {
  public let target:OpenCodeTarget
  public let sessions:[OpenCodeSession]
  public func validate()throws{
    guard !sessions.isEmpty,sessions.count<=200,sessions.first?.id==target.sessionID,
      Set(sessions.map(\.id)).count==sessions.count else{throw RemoteError.invalidResponse}
    var known=Set([target.sessionID])
    for (index,row) in sessions.enumerated(){
      guard OpenCodeIdentity.matches(row.projectID,target.projectID),OpenCodeIdentity.matches(row.location.directory,target.directory),
        row.time.updated.isFinite,!row.id.isEmpty,row.id.utf8.count<=2_048 else{throw RemoteError.conflict}
      if index>0{guard let parent=row.parentID,known.contains(parent),known.insert(row.id).inserted else{throw RemoteError.conflict}}
    }
  }
}
public protocol OpenCodeTreeServing:AnyObject,Sendable {
  func fork(target:OpenCodeTarget,beforeMessageID:String?)async throws->OpenCodeSession
  func sessionTree(target:OpenCodeTarget)async throws->OpenCodeSessionTree
  func deleteSessionTree(_ review:OpenCodeSessionTree)async throws
  func deletedSessionTree(_ review:OpenCodeSessionTree)async throws->Bool
}
extension OpenCodeClient:OpenCodeTreeServing {
  public func fork(target:OpenCodeTarget,beforeMessageID:String?)async throws->OpenCodeSession{
    let parent:OpenCodeSession,request:URLRequest
    do{
      parent=try await verifyTarget(target)
      if let beforeMessageID{guard !beforeMessageID.isEmpty,beforeMessageID.utf8.count<=2_048 else{throw RemoteError.invalidResponse}}
      guard try await !activeSessions().contains(target.sessionID) else{throw RemoteError.conflict}
      struct Body:Encodable{let before:String?}
      _=try await requireQualifiedWrites();try Task.checkCancellation()
      request=try makeRequest(segments:["api","session",target.sessionID,"fork"],method:"POST",body:JSONEncoder().encode(Body(before:beforeMessageID)))
    }catch{throw OpenCodeChatNotSubmitted(reason:(error as? RemoteError) ?? (error is CancellationError || error is OpenCodeRequestNotDispatched ? .cancelled:.unavailable))}
    var status:Int?
    do{
      let response=try await transport.data(for:request,maximumBytes:OpenCodeResponseBudget.ordinary.rawValue);status=response.1
      try checkStatus(response.1)
      struct Response:Decodable{let data:OpenCodeSession}
      let row=try JSONDecoder().decode(Response.self,from:response.0).data
      guard !row.id.isEmpty,!OpenCodeIdentity.matches(row.id,target.sessionID),row.time.archived==nil,
        OpenCodeIdentity.matches(row.projectID,target.projectID),OpenCodeIdentity.matches(row.location.directory,target.directory),
        OpenCodeModelRef.sameSelection(row.model,parent.model),OpenCodeIdentity.matches(row.agent,parent.agent),row.permissions==parent.permissions else{throw RemoteError.invalidResponse}
      return row
    }catch{
      if error is OpenCodeRequestNotDispatched{throw OpenCodeChatNotSubmitted(reason:.cancelled)}
      if let status,[400,401,403,404,413,422].contains(status){
        do{try checkStatus(status)}catch{throw OpenCodeChatNotSubmitted(reason:(error as? RemoteError) ?? .invalidResponse)}
      }
      // Native fork generates its ID on the server. Never repeat POST to discover it.
      throw RemoteError.outcomeUnknown
    }
  }
  public func sessionTree(target:OpenCodeTarget)async throws->OpenCodeSessionTree{
    let root=try await verifyTarget(target)
    var rows=[root],seen=Set([root.id]),index=0,requests=0
    while index<rows.count{
      let parent=rows[index];index+=1
      var cursor:String?,cursors=Set<String>()
      repeat{
        requests+=1;guard requests<=500 else{throw RemoteError.oversized}
        var query=[URLQueryItem(name:"limit",value:"50")]
        if let cursor{query.append(URLQueryItem(name:"cursor",value:cursor))}
        else{query.append(URLQueryItem(name:"parentID",value:parent.id));query.append(URLQueryItem(name:"order",value:"asc"))}
        let page=try await decode(OpenCodeSessionPage.self,segments:["api","session"],query:query)
        try page.cursor.validate()
        guard page.data.count<=200 else{throw RemoteError.oversized}
        for child in page.data{
          guard child.parentID==parent.id,OpenCodeIdentity.matches(child.projectID,target.projectID),
            OpenCodeIdentity.matches(child.location.directory,target.directory),seen.insert(child.id).inserted else{throw RemoteError.conflict}
          rows.append(child);guard rows.count<=200 else{throw RemoteError.oversized}
        }
        cursor=page.cursor.next
        if let cursor{guard cursors.insert(cursor).inserted else{throw RemoteError.invalidResponse}}
      }while cursor != nil
    }
    let result=OpenCodeSessionTree(target:target,sessions:rows);try result.validate();return result
  }
  public func deletedSessionTree(_ review:OpenCodeSessionTree)async throws->Bool{
    try review.validate();try validateTarget(review.target)
    var allGone=true
    for row in review.sessions{
      do{_=try await session(id:row.id);allGone=false}catch RemoteError.notFound{continue}
    }
    return allGone
  }
  public func deleteSessionTree(_ review:OpenCodeSessionTree)async throws{
    let request:URLRequest
    do{
      try review.validate()
      let current=try await sessionTree(target:review.target)
      guard current==review else{throw RemoteError.conflict}
      let active=try await activeSessions()
      guard !current.sessions.contains(where:{active.contains($0.id)}) else{throw RemoteError.conflict}
      _=try await requireQualifiedWrites();try Task.checkCancellation()
      request=try makeRequest(segments:["api","session",review.target.sessionID],method:"DELETE")
    }catch{throw OpenCodeChatNotSubmitted(reason:(error as? RemoteError) ?? (error is CancellationError || error is OpenCodeRequestNotDispatched ? .cancelled:.unavailable))}
    var status:Int?
    do{let response=try await transport.data(for:request,maximumBytes:OpenCodeResponseBudget.ordinary.rawValue);status=response.1;try checkStatus(response.1)}catch is OpenCodeRequestNotDispatched{throw OpenCodeChatNotSubmitted(reason:.cancelled)}catch{}
    if (try? await deletedSessionTree(review))==true{return}
    if let status,[400,401,403,404,413,422].contains(status){
      do{try checkStatus(status)}catch{throw OpenCodeChatNotSubmitted(reason:(error as? RemoteError) ?? .invalidResponse)}
    }
    throw RemoteError.outcomeUnknown
  }
}
