import Foundation

public struct OpenCodeChatNotSubmitted:Error,Sendable,Equatable {
  public let reason:RemoteError
  public init(reason:RemoteError){self.reason=reason}
}
/// One durable create identity. A lost acknowledgement never authorizes a new ID.
public struct OpenCodeNewChatIntent:Codable,Sendable,Equatable,Identifiable {
  public let id:String
  public let connectionID:ConnectionID
  public let projectID:String
  public let directory:String
  public let model:OpenCodeModelRef?
  public let agent:String?
  public init(id:String="ses_"+UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),
              connectionID:ConnectionID,projectID:String,directory:String,model:OpenCodeModelRef?=nil,agent:String?=nil)throws{
    self.id=id;self.connectionID=connectionID;self.projectID=projectID;self.directory=directory;self.model=model;self.agent=agent
    try validate()
  }
  public func validate()throws{
    try OpenCodeLocation.validate(directory)
    guard directory != "/",!projectID.isEmpty,projectID.utf8.count<=2_048,id.hasPrefix("ses_"),id.utf8.count<=256,
      id.utf8.allSatisfy({(48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0==95 || $0==45}),
      agent.map({!$0.isEmpty && $0.utf8.count<=2_048}) ?? true else{throw RemoteError.invalidResponse}
  }
}
public protocol OpenCodeChatServing:AnyObject,Sendable {
  func createChat(_ intent:OpenCodeNewChatIntent) async throws->OpenCodeSession
  func createdChat(for intent:OpenCodeNewChatIntent) async throws->OpenCodeSession?
  func rename(target:OpenCodeTarget,title:String,expectedTitle:String?) async throws->OpenCodeSession
}
private struct NativeCreationReceipt:Decodable,Sendable {
  let session:OpenCodeSession
  let marker:String?
  private enum CodingKeys:String,CodingKey{case metadata}
  private struct Metadata:Decodable{let pocketworkCreationID:String?}
  init(from decoder:any Decoder)throws{
    session=try OpenCodeSession(from:decoder)
    let c=try decoder.container(keyedBy:CodingKeys.self)
    marker=(try? c.decode(Metadata.self,forKey:.metadata))?.pocketworkCreationID
  }
}
private struct NativeCreationResponse:Decodable,Sendable{let data:NativeCreationReceipt}
extension OpenCodeClient:OpenCodeChatServing {
  public func createdChat(for intent:OpenCodeNewChatIntent) async throws->OpenCodeSession?{
    try intent.validate()
    guard intent.connectionID==connection.id else{throw RemoteError.conflict}
    let receipt:NativeCreationReceipt
    do{receipt=try await decode(NativeCreationResponse.self,segments:["api","session",intent.id]).data}
    catch RemoteError.notFound{return nil}
    return try verifyCreation(receipt,intent:intent)
  }
  private func verifyCreation(_ receipt:NativeCreationReceipt,intent:OpenCodeNewChatIntent)throws->OpenCodeSession{
    let actual=receipt.session
    guard OpenCodeIdentity.matches(actual.id,intent.id),OpenCodeIdentity.matches(receipt.marker,intent.id),
      OpenCodeIdentity.matches(actual.projectID,intent.projectID),OpenCodeIdentity.matches(actual.location.directory,intent.directory),
      actual.time.archived==nil,actual.time.created.isFinite,actual.time.updated.isFinite else{throw RemoteError.conflict}
    if let model=intent.model{guard OpenCodeModelRef.sameSelection(actual.model,model) else{throw RemoteError.conflict}}
    if let agent=intent.agent{guard OpenCodeIdentity.matches(actual.agent,agent) else{throw RemoteError.conflict}}
    return actual
  }
  public func createChat(_ intent:OpenCodeNewChatIntent) async throws->OpenCodeSession{
    let request:URLRequest
    do{
      try intent.validate();guard intent.connectionID==connection.id else{throw RemoteError.conflict}
      if let existing=try await createdChat(for:intent){return existing}
      let location=try await location(directory:intent.directory)
      guard OpenCodeIdentity.matches(location.project.id,intent.projectID) else{throw RemoteError.conflict}
      let scope=OpenCodeLocation(directory:intent.directory)
      if let model=intent.model{guard try await models(location:scope).contains(where:{$0.accepts(model)}) else{throw RemoteError.incompatible}}
      if let agent=intent.agent{guard try await agents(location:scope).contains(where:{$0.selectable && OpenCodeIdentity.matches($0.id,agent)}) else{throw RemoteError.incompatible}}
      struct Body:Encodable{let id:String;let location:OpenCodeLocation;let model:OpenCodeModelRef?;let agent:String?;let metadata:[String:String]}
      let body=try JSONEncoder().encode(Body(id:intent.id,location:scope,model:intent.model,agent:intent.agent,metadata:["pocketworkCreationID":intent.id]))
      _=try await requireQualifiedWrites();try Task.checkCancellation()
      request=try makeRequest(segments:["api","session"],method:"POST",body:body)
    }catch{throw OpenCodeChatNotSubmitted(reason:(error as? RemoteError) ?? (error is CancellationError || error is OpenCodeRequestNotDispatched ? .cancelled:.unavailable))}
    var status:Int?
    do{
      let result=try await transport.data(for:request,maximumBytes:OpenCodeResponseBudget.ordinary.rawValue);status=result.1
      try checkStatus(result.1)
      let receipt=try JSONDecoder().decode(NativeCreationResponse.self,from:result.0).data
      return try verifyCreation(receipt,intent:intent)
    }catch{
      if error is OpenCodeRequestNotDispatched{throw OpenCodeChatNotSubmitted(reason:.cancelled)}
      // The same random ID plus its marker can confirm a lost response. No second POST.
      if let existing=try? await createdChat(for:intent){return existing}
      if let status,[400,401,403,404,413,422].contains(status){
        let reason:RemoteError
        do{try checkStatus(status);reason = .invalidResponse}catch{reason=(error as? RemoteError) ?? .invalidResponse}
        throw OpenCodeChatNotSubmitted(reason:reason)
      }
      throw RemoteError.outcomeUnknown
    }
  }
  public func rename(target:OpenCodeTarget,title:String,expectedTitle:String?) async throws->OpenCodeSession{
    let name=title.trimmingCharacters(in:.whitespacesAndNewlines),request:URLRequest
    do{
      guard !name.isEmpty,name.unicodeScalars.count<=200,!name.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}) else{throw RemoteError.invalidResponse}
      let before=try await verifyTarget(target)
      if OpenCodeIdentity.matches(before.title,name){return before}
      guard OpenCodeIdentity.matches(before.title,expectedTitle) else{throw RemoteError.conflict}
      struct Body:Encodable{let title:String}
      _=try await requireQualifiedWrites();try Task.checkCancellation()
      request=try makeRequest(segments:["api","session",target.sessionID],method:"PATCH",body:JSONEncoder().encode(Body(title:name)))
    }catch{throw OpenCodeChatNotSubmitted(reason:(error as? RemoteError) ?? (error is CancellationError || error is OpenCodeRequestNotDispatched ? .cancelled:.unavailable))}
    var status:Int?
    do{let result=try await transport.data(for:request,maximumBytes:OpenCodeResponseBudget.ordinary.rawValue);status=result.1;try checkStatus(result.1)}catch is OpenCodeRequestNotDispatched{throw OpenCodeChatNotSubmitted(reason:.cancelled)}catch{}
    if let actual=try? await verifyTarget(target),OpenCodeIdentity.matches(actual.title,name){return actual}
    if let status,[400,401,403,404,413,422].contains(status){
      do{try checkStatus(status)}catch{throw OpenCodeChatNotSubmitted(reason:(error as? RemoteError) ?? .invalidResponse)}
    }
    throw RemoteError.outcomeUnknown
  }
}
